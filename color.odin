package main

import "core:math"


Lab :: struct {
	L, a, b: f32,
}
RGB :: struct {
	r, g, b: f32,
}
HSV :: struct {
	h, s, v: f32,
}
LC :: struct {
	L, C: f32,
}
ST :: struct {
	S, T: f32,
}

K1 :: 0.206
K2 :: 0.03
K3 :: (1 + K1) / (1 + K2)

toe :: proc(x: f32) -> f32 {
	return 0.5 * (K3 * x - K1 + math.sqrt((K3 * x - K1) * (K3 * x - K1) + 4 * K2 * K3 * x))
}

toe_inv :: proc(x: f32) -> f32 {
	return (x * x + K1 * x) / (K3 * (x + K2))
}

to_ST :: proc(cusp: LC) -> ST {
	L := cusp.L
	C := cusp.C
	return {C / L, C / (1 - L)}
}

oklab_to_linear_srgb :: proc(c: Lab) -> RGB {
	l_ := c.L + 0.3963377774 * c.a + 0.2158037573 * c.b
	m_ := c.L - 0.1055613458 * c.a - 0.0638541728 * c.b
	s_ := c.L - 0.0894841775 * c.a - 1.2914855480 * c.b

	l := l_ * l_ * l_
	m := m_ * m_ * m_
	s := s_ * s_ * s_

	return {
		+4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
	}
}

// finds L_cusp and C_cusp for a given hue
// a and b must be normalized so a^2 + b^2 == 1
find_cusp :: proc(a, b: f32) -> LC {
	// First, find the maximum saturation (saturation S = C/L)
	S_cusp := compute_max_saturation(a, b)

	// Convert to linear sRGB to find the first point where at least one of r,g or b >= 1:
	rgb_at_max := oklab_to_linear_srgb({1, S_cusp * a, S_cusp * b})
	L_cusp := cbrt(1.0 / max(max(rgb_at_max.r, rgb_at_max.g), rgb_at_max.b))
	C_cusp := L_cusp * S_cusp

	return {L_cusp, C_cusp}
}

okhsv_to_srgb :: proc(hsv: HSV) -> RGB {
	h := hsv.h
	s := hsv.s
	v := hsv.v

	a_ := math.cos(2 * math.PI * h)
	b_ := math.sin(2 * math.PI * h)

	cusp := find_cusp(a_, b_)
	ST_max := to_ST(cusp)
	S_max := ST_max.S
	T_max := ST_max.T
	S_0 := f32(0.5)
	k := 1 - S_0 / S_max

	// first we compute L and V as if the gamut is a perfect triangle:

	// L, C when v==1:
	L_v := 1 - s * S_0 / (S_0 + T_max - T_max * k * s)
	C_v := s * T_max * S_0 / (S_0 + T_max - T_max * k * s)

	L := v * L_v
	C := v * C_v

	// then we compensate for both toe and the curved top part of the triangle:
	L_vt := toe_inv(L_v)
	C_vt := C_v * L_vt / L_v

	L_new := toe_inv(L)
	C = C * L_new / L
	L = L_new

	rgb_scale := oklab_to_linear_srgb({L_vt, a_ * C_vt, b_ * C_vt})
	scale_L := cbrt(1.0 / max(max(rgb_scale.r, rgb_scale.g), max(rgb_scale.b, 0)))

	L = L * scale_L
	C = C * scale_L

	rgb := oklab_to_linear_srgb({L, C * a_, C * b_})
	return {
		srgb_transfer_function(rgb.r),
		srgb_transfer_function(rgb.g),
		srgb_transfer_function(rgb.b),
	}
}

srgb_to_okhsv :: proc(rgb: RGB) -> HSV {
	lab := linear_srgb_to_oklab(
		{
			srgb_transfer_function_inv(rgb.r / 255),
			srgb_transfer_function_inv(rgb.g / 255),
			srgb_transfer_function_inv(rgb.b / 255),
		},
	)

	C := math.sqrt(lab.a * lab.a + lab.b * lab.b)
	a_ := lab.a / C
	b_ := lab.b / C

	L := lab.L
	h := 0.5 + 0.5 * math.atan2(-lab.b, -lab.a) / math.PI

	cusp := find_cusp(a_, b_)
	ST_max := to_ST(cusp)
	S_max := ST_max.S
	T_max := ST_max.T
	S_0 := f32(0.5)
	k := 1 - S_0 / S_max

	// first we find L_v, C_v, L_vt and C_vt

	t := T_max / (C + L * T_max)
	L_v := t * L
	C_v := t * C

	L_vt := toe_inv(L_v)
	C_vt := C_v * L_vt / L_v

	// we can then use these to invert the step that compensates for the toe and the curved top part of the triangle:
	rgb_scale := oklab_to_linear_srgb({L_vt, a_ * C_vt, b_ * C_vt})
	scale_L := cbrt(1.0 / max(max(rgb_scale.r, rgb_scale.g), max(rgb_scale.b, 0.0)))

	L = L / scale_L
	C = C / scale_L

	C = C * toe(L) / L
	L = toe(L)

	// we can now compute v and s:

	v := L / L_v
	s := (S_0 + T_max) * C_v / ((T_max * S_0) + T_max * k * C_v)

	return {h, s, v}
}

// from linear
srgb_transfer_function :: proc(a: f32) -> f32 {
	return .0031308 >= a ? 12.92 * a : 1.055 * math.pow(a, 1.0 / 2.4) - .055
}

// to linear
srgb_transfer_function_inv :: proc(a: f32) -> f32 {
	return .04045 < a ? math.pow((a + .055) / 1.055, 2.4) : a / 12.92
}

linear_srgb_to_oklab :: proc(c: RGB) -> Lab {
	l := 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b
	m := 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b
	s := 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b

	l_ := cbrt(l)
	m_ := cbrt(m)
	s_ := cbrt(s)

	return {
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
	}
}

// Finds the maximum saturation possible for a given hue that fits in sRGB
// Saturation here is defined as S = C/L
// a and b must be normalized so a^2 + b^2 == 1
compute_max_saturation :: proc(a, b: f32) -> f32 {
	// Max saturation will be when one of r, g or b goes below zero.

	// Select different coefficients depending on which component goes below zero first
	k0, k1, k2, k3, k4, wl, wm, ws: f32

	if -1.88170328 * a - 0.80936493 * b > 1 {
		// Red component
		k0 = +1.19086277;k1 = +1.76576728;k2 = +0.59662641;k3 = +0.75515197;k4 = +0.56771245
		wl = +4.0767416621;wm = -3.3077115913;ws = +0.2309699292
	} else if 1.81444104 * a - 1.19445276 * b > 1 {
		// Green component
		k0 = +0.73956515;k1 = -0.45954404;k2 = +0.08285427;k3 = +0.12541070;k4 = +0.14503204
		wl = -1.2684380046;wm = +2.6097574011;ws = -0.3413193965
	} else {
		// Blue component
		k0 = +1.35733652;k1 = -0.00915799;k2 = -1.15130210;k3 = -0.50559606;k4 = +0.00692167
		wl = -0.0041960863;wm = -0.7034186147;ws = +1.7076147010
	}

	// Approximate max saturation using a polynomial:
	S := k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b

	// Do one step Halley's method to get closer
	// this gives an error less than 10e6, except for some blue hues where the dS/dh is close to infinite
	// this should be sufficient for most applications, otherwise do two/three steps 

	k_l := +0.3963377774 * a + 0.2158037573 * b
	k_m := -0.1055613458 * a - 0.0638541728 * b
	k_s := -0.0894841775 * a - 1.2914855480 * b

	{
		l_ := 1 + S * k_l
		m_ := 1 + S * k_m
		s_ := 1 + S * k_s

		l := l_ * l_ * l_
		m := m_ * m_ * m_
		s := s_ * s_ * s_

		l_dS := 3 * k_l * l_ * l_
		m_dS := 3 * k_m * m_ * m_
		s_dS := 3 * k_s * s_ * s_

		l_dS2 := 6 * k_l * k_l * l_
		m_dS2 := 6 * k_m * k_m * m_
		s_dS2 := 6 * k_s * k_s * s_

		f := wl * l + wm * m + ws * s
		f1 := wl * l_dS + wm * m_dS + ws * s_dS
		f2 := wl * l_dS2 + wm * m_dS2 + ws * s_dS2

		S = S - f * f1 / (f1 * f1 - 0.5 * f * f2)
	}

	return S
}

EPS :: 0.0001
clamp_eps :: proc(x: f32) -> f32 {return x < EPS ? EPS : x > 1 - EPS ? 1 - EPS : x}

cbrt :: proc(x: f32) -> f32 {return math.pow(x, 1.0 / 3.0)}
