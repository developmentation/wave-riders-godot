#[compute]
#version 450
/**
 * Wave Riders ocean: initial spectrum h0(k) for one cascade.
 * Wind sea: JONSWAP/TMA with Hasselmann directional spreading (after GodotOceanWaves, MIT, Ethan Truong).
 * Swell: narrow Gaussian in frequency with a Longuet-Higgins spread, normalised so its integral is m0.
 * The cascade is band-limited to [k_lo, k_hi) so the three cascades never double-count energy.
 * Amplitude convention: E|h0|^2 = P(k)/2 (gaussian() has E|g|^2 = 2, hence the 0.25), so that
 * sum_k E|h0(k) e^{iwt} + conj(h0(-k)) e^{-iwt}|^2 = sum_k (P(k) + P(-k))/2 = m0 exactly.
 */
#define PI (3.141592653589793)
#define G  (9.81)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) restrict writeonly uniform image2DArray spectrum;

layout(push_constant) restrict readonly uniform PushConstants {
	ivec2 seed;
	vec2 tile_length;
	float alpha;
	float peak_omega;
	float wind_speed;
	float wind_angle;   // atan2(z, x) of the direction the wind waves travel toward, flipped for the +wt time sign
	float depth;
	float swell_amp;    // Gaussian peak spectral density (m^2 s)
	float swell_omega;
	float swell_sigma;
	float swell_angle;
	float spread;       // 0 = fully directional, 1 = isotropic
	float detail;       // attenuates the shortest waves
	float k_lo;
	float k_hi;
	uint cascade_index;
};

vec2 hash(in uvec2 x) {
	uint h32 = x.y + 374761393U + x.x * 3266489917U;
	h32 = 2246822519U * (h32 ^ (h32 >> 15));
	h32 = 3266489917U * (h32 ^ (h32 >> 13));
	uint n = h32 ^ (h32 >> 16);
	uvec2 rz = uvec2(n, n * 48271U);
	return vec2((rz.xy >> 1) & uvec2(0x7FFFFFFFU)) / float(0x7FFFFFFF);
}

vec2 gaussian(in vec2 x) {
	float r = sqrt(-2.0 * log(max(x.x, 1e-7)));
	float theta = 2.0 * PI * x.y;
	return vec2(r * cos(theta), r * sin(theta));
}

vec2 dispersion_relation(in float k) {
	float a = k * depth;
	float b = tanh(a);
	float w = sqrt(G * k * b);
	float dw = 0.5 * G * (b + a * (1.0 - b * b)) / max(w, 1e-6);
	return vec2(w, dw);
}

float longuet_higgins_normalization(in float s) {
	float a = sqrt(s);
	return (s < 0.4) ? (0.5 / PI) + s * (0.220636 + s * (-0.109 + s * 0.090)) : inversesqrt(PI) * (a * 0.5 + (1.0 / a) * 0.0625);
}

float longuet_higgins_function(in float s, in float theta) {
	return longuet_higgins_normalization(s) * pow(abs(cos(theta * 0.5)), 2.0 * s);
}

float hasselmann_directional_spread(in float w, in float w_p, in float u, in float theta) {
	float p = w / w_p;
	float s = (w <= w_p) ? 6.97 * pow(abs(p), 4.06) : 9.77 * pow(abs(p), -2.33 - 1.45 * (u * w_p / G - 1.17));
	s = clamp(s, 0.5, 60.0);
	return longuet_higgins_function(s, theta);
}

float TMA_spectrum(in float w, in float w_p, in float a) {
	const float beta = 1.25;
	const float gamma = 3.3;
	float sigma = (w <= w_p) ? 0.07 : 0.09;
	float r = exp(-(w - w_p) * (w - w_p) / (2.0 * sigma * sigma * w_p * w_p));
	float jonswap = (a * G * G) / pow(w, 5.0) * exp(-beta * pow(w_p / w, 4.0)) * pow(gamma, r);
	float w_h = min(w * sqrt(depth / G), 2.0);
	float kitaigorodskii = (w_h <= 1.0) ? 0.5 * w_h * w_h : 1.0 - 0.5 * (2.0 - w_h) * (2.0 - w_h);
	return jonswap * kitaigorodskii;
}

vec2 spectrum_amplitude(in ivec2 id, in ivec2 dims) {
	vec2 dk = 2.0 * PI / tile_length;
	vec2 k_vec = vec2(id - dims / 2) * dk;
	float k = length(k_vec) + 1e-6;
	if (k < k_lo || k >= k_hi) return vec2(0.0);
	// World-space wave vector is (k.y, k.x) because the second FFT pass leaves the field transposed.
	float theta = atan(k_vec.x, k_vec.y);

	vec2 disp = dispersion_relation(k);
	float w = disp.x;
	float w_norm = disp.y / k * dk.x * dk.y;   // Jacobian of (kx,ky) -> (w,theta) times the bin area

	float s_wind = (alpha > 0.0) ? TMA_spectrum(w, peak_omega, alpha) : 0.0;
	float d_wind = mix(hasselmann_directional_spread(w, peak_omega, wind_speed, theta - wind_angle), 0.5 / PI, spread);

	float s_swell = swell_amp * exp(-(w - swell_omega) * (w - swell_omega) / (2.0 * swell_sigma * swell_sigma));
	float d_swell = mix(longuet_higgins_function(28.0, theta - swell_angle), 0.5 / PI, spread * 0.35);

	float short_wave_atten = exp(-(1.0 - detail) * (1.0 - detail) * k * k);
	float p = (s_wind * d_wind + s_swell * d_swell) * w_norm * short_wave_atten;
	return gaussian(hash(uvec2(id + seed))) * sqrt(max(p, 0.0) * 0.25);
}

void main() {
	const ivec2 dims = imageSize(spectrum).xy;
	const ivec3 id = ivec3(gl_GlobalInvocationID.xy, cascade_index);
	const ivec2 id0 = id.xy;
	const ivec2 id1 = ivec2(mod(-id0, dims));
	vec2 h0 = spectrum_amplitude(id0, dims);
	vec2 h0m = spectrum_amplitude(id1, dims);
	imageStore(spectrum, id, vec4(h0, h0m.x, -h0m.y));
}
