// MIT License

// Copyright (c) 2019-2021 bloc97
// All rights reserved.

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//!DESC Anime4K-v4.0-De-Ring-Compute-Statistics
//!HOOK MAIN
//!BIND HOOKED
//!SAVE STATSMAX
//!COMPONENTS 1

#define KERNELSIZE 5 //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE 2 //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).

float get_luma(vec4 rgba) {
	return dot(vec4(0.299, 0.587, 0.114, 0.0), rgba);
}

vec4 hook() {

	float gmax = 0.0;
	
	for (int i=0; i<KERNELSIZE; i++) {
		float g = get_luma(MAIN_texOff(vec2(i - KERNELHALFSIZE, 0)));
		
		gmax = max(g, gmax);
	}
	
	return vec4(gmax, 0.0, 0.0, 0.0);
}

//!DESC Anime4K-v4.0-De-Ring-Compute-Statistics
//!HOOK MAIN
//!BIND HOOKED
//!BIND STATSMAX
//!SAVE STATSMAX
//!COMPONENTS 1

#define KERNELSIZE 5 //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE 2 //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).

vec4 hook() {

	float gmax = 0.0;
	
	for (int i=0; i<KERNELSIZE; i++) {
		float g = STATSMAX_texOff(vec2(0, i - KERNELHALFSIZE)).x;
		
		gmax = max(g, gmax);
	}
	
	return vec4(gmax, 0.0, 0.0, 0.0);
}

//!DESC Anime4K-v4.0-De-Ring-Clamp
//!HOOK PREKERNEL
//!BIND HOOKED
//!BIND STATSMAX

float get_luma(vec4 rgba) {
	return dot(vec4(0.299, 0.587, 0.114, 0.0), rgba);
}

vec4 hook() {

	float current_luma = get_luma(HOOKED_tex(HOOKED_pos));
	float new_luma = min(current_luma, STATSMAX_tex(HOOKED_pos).x);
	
	//This trick is only possible if the inverse Y->RGB matrix has 1 for every row... (which is the case for BT.709)
	//Otherwise we would need to convert RGB to YUV, modify Y then convert back to RGB.
    return HOOKED_tex(HOOKED_pos) - (current_luma - new_luma); 
}// Copyright (c) 2021 Advanced Micro Devices, Inc. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// FidelityFX FSR v1.0.2 by AMD
// ported to mpv by agyild

// Changelog
// Made it compatible with pre-OpenGL 4.0 renderers
// Made it directly operate on LUMA plane, since the original shader was operating on LUMA by deriving it from RGB. This should cause a major increase in performance, especially on OpenGL 4.0+ renderers (4+2 texture lookups vs. 12+5)
// Removed transparency preservation mechanism since the alpha channel is a separate source plane than LUMA
// Added optional performance-saving lossy optimizations to EASU (Credit: atyuwen, https://atyuwen.github.io/posts/optimizing-fsr/)
// 
// Notes
// Per AMD's guidelines only upscales content up to 4x (e.g., 1080p -> 2160p, 720p -> 1440p etc.) and everything else in between,
// that means FSR will scale up to 4x at maximum, and any further scaling will be processed by mpv's scalers

//!HOOK LUMA
//!BIND HOOKED
//!SAVE EASUTEX
//!DESC FidelityFX Super Resolution v1.0.2 (EASU)
//!WHEN OUTPUT.w OUTPUT.h * LUMA.w LUMA.h * / 1.0 >
//!WIDTH OUTPUT.w OUTPUT.w LUMA.w 2 * < * LUMA.w 2 * OUTPUT.w LUMA.w 2 * > * + OUTPUT.w OUTPUT.w LUMA.w 2 * = * +
//!HEIGHT OUTPUT.h OUTPUT.h LUMA.h 2 * < * LUMA.h 2 * OUTPUT.h LUMA.h 2 * > * + OUTPUT.h OUTPUT.h LUMA.h 2 * = * +
//!COMPONENTS 1

// User variables - EASU
#define FSR_PQ 0 // Whether the source content has PQ gamma or not. Needs to be set to the same value for both passes. 0 or 1.
#define FSR_EASU_DERING 1 // If set to 0, disables deringing for a small increase in performance. 0 or 1.
#define FSR_EASU_SIMPLE_ANALYSIS 0 // If set to 1, uses a simpler single-pass direction and length analysis for an increase in performance. 0 or 1.
#define FSR_EASU_QUIT_EARLY 0 // If set to 1, uses bilinear filtering for non-edge pixels and skips EASU on those regions for an increase in performance. 0 or 1.

// Shader code

#ifndef FSR_EASU_DIR_THRESHOLD
	#if (FSR_EASU_QUIT_EARLY == 1)
		#define FSR_EASU_DIR_THRESHOLD 64.0
	#elif (FSR_EASU_QUIT_EARLY == 0)
		#define FSR_EASU_DIR_THRESHOLD 32768.0
	#endif
#endif

float APrxLoRcpF1(float a) {
	return uintBitsToFloat(uint(0x7ef07ebb) - floatBitsToUint(a));
}

float APrxLoRsqF1(float a) {
	return uintBitsToFloat(uint(0x5f347d74) - (floatBitsToUint(a) >> uint(1)));
}

float AMin3F1(float x, float y, float z) {
	return min(x, min(y, z));
}

float AMax3F1(float x, float y, float z) {
	return max(x, max(y, z));
}

#if (FSR_PQ == 1)

float ToGamma2(float a) { 
	return pow(a, 4.0);
}

#endif

 // Filtering for a given tap for the scalar.
 void FsrEasuTap(
	inout float aC,	// Accumulated color, with negative lobe.
	inout float aW, // Accumulated weight.
	vec2 off,       // Pixel offset from resolve position to tap.
	vec2 dir,       // Gradient direction.
	vec2 len,       // Length.
	float lob,      // Negative lobe strength.
	float clp,		// Clipping point.
	float c){		// Tap color.
	// Rotate offset by direction.
	vec2 v;
	v.x = (off.x * ( dir.x)) + (off.y * dir.y);
	v.y = (off.x * (-dir.y)) + (off.y * dir.x);
	// Anisotropy.
	v *= len;
	// Compute distance^2.
	float d2 = v.x * v.x + v.y * v.y;
	// Limit to the window as at corner, 2 taps can easily be outside.
	d2 = min(d2, clp);
	// Approximation of lancos2 without sin() or rcp(), or sqrt() to get x.
	//  (25/16 * (2/5 * x^2 - 1)^2 - (25/16 - 1)) * (1/4 * x^2 - 1)^2
	//  |_______________________________________|   |_______________|
	//                   base                             window
	// The general form of the 'base' is,
	//  (a*(b*x^2-1)^2-(a-1))
	// Where 'a=1/(2*b-b^2)' and 'b' moves around the negative lobe.
	float wB = float(2.0 / 5.0) * d2 + -1.0;
	float wA = lob * d2 + -1.0;
	wB *= wB;
	wA *= wA;
	wB = float(25.0 / 16.0) * wB + float(-(25.0 / 16.0 - 1.0));
	float w = wB * wA;
	// Do weighted average.
	aC += c * w;
	aW += w;
}

// Accumulate direction and length.
void FsrEasuSet(
	inout vec2 dir,
	inout float len,
	vec2 pp,
#if (FSR_EASU_SIMPLE_ANALYSIS == 1)
	float b, float c,
	float i, float j, float f, float e,
	float k, float l, float h, float g,
	float o, float n
#elif (FSR_EASU_SIMPLE_ANALYSIS == 0)
	bool biS, bool biT, bool biU, bool biV,
	float lA, float lB, float lC, float lD, float lE
#endif
	){
	// Compute bilinear weight, branches factor out as predicates are compiler time immediates.
	//  s t
	//  u v
#if (FSR_EASU_SIMPLE_ANALYSIS == 1)
	vec4 w = vec4(0.0);
	w.x = (1.0 - pp.x) * (1.0 - pp.y);
	w.y =        pp.x  * (1.0 - pp.y);
	w.z = (1.0 - pp.x) *        pp.y;
	w.w =        pp.x  *        pp.y;

	float lA = dot(w, vec4(b, c, f, g));
	float lB = dot(w, vec4(e, f, i, j));
	float lC = dot(w, vec4(f, g, j, k));
	float lD = dot(w, vec4(g, h, k, l));
	float lE = dot(w, vec4(j, k, n, o));
#elif (FSR_EASU_SIMPLE_ANALYSIS == 0)
	float w = 0.0;
	if (biS)
		w = (1.0 - pp.x) * (1.0 - pp.y);
	if (biT)
		w =        pp.x  * (1.0 - pp.y);
	if (biU)
		w = (1.0 - pp.x) *        pp.y;
	if (biV)
		w =        pp.x  *        pp.y;
#endif
	// Direction is the '+' diff.
	//    a
	//  b c d
	//    e
	// Then takes magnitude from abs average of both sides of 'c'.
	// Length converts gradient reversal to 0, smoothly to non-reversal at 1, shaped, then adding horz and vert terms.
	float dc = lD - lC;
	float cb = lC - lB;
	float lenX = max(abs(dc), abs(cb));
	lenX = APrxLoRcpF1(lenX);
	float dirX = lD - lB;
	lenX = clamp(abs(dirX) * lenX, 0.0, 1.0);
	lenX *= lenX;
	// Repeat for the y axis.
	float ec = lE - lC;
	float ca = lC - lA;
	float lenY = max(abs(ec), abs(ca));
	lenY = APrxLoRcpF1(lenY);
	float dirY = lE - lA;
	lenY = clamp(abs(dirY) * lenY, 0.0, 1.0);
	lenY *= lenY;
#if (FSR_EASU_SIMPLE_ANALYSIS == 1)
	len = lenX + lenY;
	dir = vec2(dirX, dirY);
#elif (FSR_EASU_SIMPLE_ANALYSIS == 0)
	dir += vec2(dirX, dirY) * w;
	len += dot(vec2(w), vec2(lenX, lenY));
#endif
}

vec4 hook() {
	// Result
	vec4 pix = vec4(0.0, 0.0, 0.0, 1.0);

	//------------------------------------------------------------------------------------------------------------------------------
	//      +---+---+
	//      |   |   |
	//      +--(0)--+
	//      | b | c |
	//  +---F---+---+---+
	//  | e | f | g | h |
	//  +--(1)--+--(2)--+
	//  | i | j | k | l |
	//  +---+---+---+---+
	//      | n | o |
	//      +--(3)--+
	//      |   |   |
	//      +---+---+
	// Get position of 'F'.
	vec2 pp = HOOKED_pos * HOOKED_size - vec2(0.5);
	vec2 fp = floor(pp);
	pp -= fp;
	//------------------------------------------------------------------------------------------------------------------------------
	// 12-tap kernel.
	//    b c
	//  e f g h
	//  i j k l
	//    n o
	// Gather 4 ordering.
	//  a b
	//  r g
	// Allowing dead-code removal to remove the 'z's.
#if (defined(HOOKED_gather) && (__VERSION__ >= 400 || (GL_ES && __VERSION__ >= 310)))
	vec4 bczzL = HOOKED_gather(vec2((fp + vec2(1.0, -1.0)) * HOOKED_pt), 0);
	vec4 ijfeL = HOOKED_gather(vec2((fp + vec2(0.0,  1.0)) * HOOKED_pt), 0);
	vec4 klhgL = HOOKED_gather(vec2((fp + vec2(2.0,  1.0)) * HOOKED_pt), 0);
	vec4 zzonL = HOOKED_gather(vec2((fp + vec2(1.0,  3.0)) * HOOKED_pt), 0);
#else
	// pre-OpenGL 4.0 compatibility
	float b = HOOKED_tex(vec2((fp + vec2(0.5, -0.5)) * HOOKED_pt)).r;
	float c = HOOKED_tex(vec2((fp + vec2(1.5, -0.5)) * HOOKED_pt)).r;
	
	float e = HOOKED_tex(vec2((fp + vec2(-0.5, 0.5)) * HOOKED_pt)).r;
	float f = HOOKED_tex(vec2((fp + vec2( 0.5, 0.5)) * HOOKED_pt)).r;
	float g = HOOKED_tex(vec2((fp + vec2( 1.5, 0.5)) * HOOKED_pt)).r;
	float h = HOOKED_tex(vec2((fp + vec2( 2.5, 0.5)) * HOOKED_pt)).r;
	
	float i = HOOKED_tex(vec2((fp + vec2(-0.5, 1.5)) * HOOKED_pt)).r;
	float j = HOOKED_tex(vec2((fp + vec2( 0.5, 1.5)) * HOOKED_pt)).r;
	float k = HOOKED_tex(vec2((fp + vec2( 1.5, 1.5)) * HOOKED_pt)).r;
	float l = HOOKED_tex(vec2((fp + vec2( 2.5, 1.5)) * HOOKED_pt)).r;
	
	float n = HOOKED_tex(vec2((fp + vec2(0.5, 2.5) ) * HOOKED_pt)).r;
	float o = HOOKED_tex(vec2((fp + vec2(1.5, 2.5) ) * HOOKED_pt)).r;

	vec4 bczzL = vec4(b, c, 0.0, 0.0);
	vec4 ijfeL = vec4(i, j, f, e);
	vec4 klhgL = vec4(k, l, h, g);
	vec4 zzonL = vec4(0.0, 0.0, o, n);
#endif
	//------------------------------------------------------------------------------------------------------------------------------
	// Rename.
	float bL = bczzL.x;
	float cL = bczzL.y;
	float iL = ijfeL.x;
	float jL = ijfeL.y;
	float fL = ijfeL.z;
	float eL = ijfeL.w;
	float kL = klhgL.x;
	float lL = klhgL.y;
	float hL = klhgL.z;
	float gL = klhgL.w;
	float oL = zzonL.z;
	float nL = zzonL.w;

#if (FSR_PQ == 1)
	// Not the most performance-friendly solution, but should work until mpv adds proper gamma transformation functions for shaders
	bL = ToGamma2(bL);
	cL = ToGamma2(cL);
	iL = ToGamma2(iL);
	jL = ToGamma2(jL);
	fL = ToGamma2(fL);
	eL = ToGamma2(eL);
	kL = ToGamma2(kL);
	lL = ToGamma2(lL);
	hL = ToGamma2(hL);
	gL = ToGamma2(gL);
	oL = ToGamma2(oL);
	nL = ToGamma2(nL);
#endif

	// Accumulate for bilinear interpolation.
	vec2 dir = vec2(0.0);
	float len = 0.0;
#if (FSR_EASU_SIMPLE_ANALYSIS == 1)
	FsrEasuSet(dir, len, pp, bL, cL, iL, jL, fL, eL, kL, lL, hL, gL, oL, nL);
#elif (FSR_EASU_SIMPLE_ANALYSIS == 0)
	FsrEasuSet(dir, len, pp, true, false, false, false, bL, eL, fL, gL, jL);
	FsrEasuSet(dir, len, pp, false, true, false, false, cL, fL, gL, hL, kL);
	FsrEasuSet(dir, len, pp, false, false, true, false, fL, iL, jL, kL, nL);
	FsrEasuSet(dir, len, pp, false, false, false, true, gL, jL, kL, lL, oL);
#endif
	//------------------------------------------------------------------------------------------------------------------------------
	// Normalize with approximation, and cleanup close to zero.
	vec2 dir2 = dir * dir;
	float dirR = dir2.x + dir2.y;
	bool zro = dirR < float(1.0 / FSR_EASU_DIR_THRESHOLD);
	dirR = APrxLoRsqF1(dirR);
#if (FSR_EASU_QUIT_EARLY == 1)
	if (zro) {
		vec4 w = vec4(0.0);
		w.x = (1.0 - pp.x) * (1.0 - pp.y);
		w.y =        pp.x  * (1.0 - pp.y);
		w.z = (1.0 - pp.x) *        pp.y;
		w.w =        pp.x  *        pp.y;

		pix.r = clamp(dot(w, vec4(fL, gL, jL, kL)), 0.0, 1.0);
		return pix;
	}
#elif (FSR_EASU_QUIT_EARLY == 0)
	dirR = zro ? 1.0 : dirR;
	dir.x = zro ? 1.0 : dir.x;
#endif
	dir *= vec2(dirR);
	// Transform from {0 to 2} to {0 to 1} range, and shape with square.
	len = len * 0.5;
	len *= len;
	// Stretch kernel {1.0 vert|horz, to sqrt(2.0) on diagonal}.
	float stretch = (dir.x * dir.x + dir.y * dir.y) * APrxLoRcpF1(max(abs(dir.x), abs(dir.y)));
	// Anisotropic length after rotation,
	//  x := 1.0 lerp to 'stretch' on edges
	//  y := 1.0 lerp to 2x on edges
	vec2 len2 = vec2(1.0 + (stretch - 1.0) * len, 1.0 + -0.5 * len);
	// Based on the amount of 'edge',
	// the window shifts from +/-{sqrt(2.0) to slightly beyond 2.0}.
	float lob = 0.5 + float((1.0 / 4.0 - 0.04) - 0.5) * len;
	// Set distance^2 clipping point to the end of the adjustable window.
	float clp = APrxLoRcpF1(lob);
	//------------------------------------------------------------------------------------------------------------------------------
	// Accumulation
	//    b c
	//  e f g h
	//  i j k l
	//    n o
	float aC = 0.0;
	float aW = 0.0;
	FsrEasuTap(aC, aW, vec2( 0.0,-1.0) - pp, dir, len2, lob, clp, bL); // b
	FsrEasuTap(aC, aW, vec2( 1.0,-1.0) - pp, dir, len2, lob, clp, cL); // c
	FsrEasuTap(aC, aW, vec2(-1.0, 1.0) - pp, dir, len2, lob, clp, iL); // i
	FsrEasuTap(aC, aW, vec2( 0.0, 1.0) - pp, dir, len2, lob, clp, jL); // j
	FsrEasuTap(aC, aW, vec2( 0.0, 0.0) - pp, dir, len2, lob, clp, fL); // f
	FsrEasuTap(aC, aW, vec2(-1.0, 0.0) - pp, dir, len2, lob, clp, eL); // e
	FsrEasuTap(aC, aW, vec2( 1.0, 1.0) - pp, dir, len2, lob, clp, kL); // k
	FsrEasuTap(aC, aW, vec2( 2.0, 1.0) - pp, dir, len2, lob, clp, lL); // l
	FsrEasuTap(aC, aW, vec2( 2.0, 0.0) - pp, dir, len2, lob, clp, hL); // h
	FsrEasuTap(aC, aW, vec2( 1.0, 0.0) - pp, dir, len2, lob, clp, gL); // g
	FsrEasuTap(aC, aW, vec2( 1.0, 2.0) - pp, dir, len2, lob, clp, oL); // o
	FsrEasuTap(aC, aW, vec2( 0.0, 2.0) - pp, dir, len2, lob, clp, nL); // n
	//------------------------------------------------------------------------------------------------------------------------------
	// Normalize and dering.
	pix.r = aC / aW;
#if (FSR_EASU_DERING == 1)
	float min1 = min(AMin3F1(fL, gL, jL), kL);
	float max1 = max(AMax3F1(fL, gL, jL), kL);
	pix.r = clamp(pix.r, min1, max1);
#endif
	pix.r = clamp(pix.r, 0.0, 1.0);

	return pix;
}

//!HOOK LUMA
//!BIND EASUTEX
//!DESC FidelityFX Super Resolution v1.0.2 (RCAS)
//!WIDTH EASUTEX.w
//!HEIGHT EASUTEX.h
//!COMPONENTS 1

// User variables - RCAS
#define SHARPNESS 0.2 // Controls the amount of sharpening. The scale is {0.0 := maximum, to N>0, where N is the number of stops (halving) of the reduction of sharpness}. 0.0 to 2.0.
#define FSR_RCAS_DENOISE 1 // If set to 1, lessens the sharpening on noisy areas. Can be disabled for better performance. 0 or 1.
#define FSR_PQ 0 // Whether the source content has PQ gamma or not. Needs to be set to the same value for both passes. 0 or 1.

// Shader code

#define FSR_RCAS_LIMIT (0.25 - (1.0 / 16.0)) // This is set at the limit of providing unnatural results for sharpening.

float APrxMedRcpF1(float a) {
	float b = uintBitsToFloat(uint(0x7ef19fff) - floatBitsToUint(a));
	return b * (-b * a + 2.0);
}

float AMax3F1(float x, float y, float z) {
	return max(x, max(y, z)); 
}

float AMin3F1(float x, float y, float z) {
	return min(x, min(y, z));
}

#if (FSR_PQ == 1)

float FromGamma2(float a) { 
	return sqrt(sqrt(a));
}

#endif

vec4 hook() {
	// Algorithm uses minimal 3x3 pixel neighborhood.
	//    b 
	//  d e f
	//    h
#if (defined(EASUTEX_gather) && (__VERSION__ >= 400 || (GL_ES && __VERSION__ >= 310)))
	vec3 bde = EASUTEX_gather(EASUTEX_pos + EASUTEX_pt * vec2(-0.5), 0).xyz;
	float b = bde.z;
	float d = bde.x;
	float e = bde.y;

	vec2 fh = EASUTEX_gather(EASUTEX_pos + EASUTEX_pt * vec2(0.5), 0).zx;
	float f = fh.x;
	float h = fh.y;
#else
	float b = EASUTEX_texOff(vec2( 0.0, -1.0)).r;
	float d = EASUTEX_texOff(vec2(-1.0,  0.0)).r;
	float e = EASUTEX_tex(EASUTEX_pos).r;
	float f = EASUTEX_texOff(vec2(1.0, 0.0)).r;
	float h = EASUTEX_texOff(vec2(0.0, 1.0)).r;
#endif

	// Min and max of ring.
	float mn1L = min(AMin3F1(b, d, f), h);
	float mx1L = max(AMax3F1(b, d, f), h);

	// Immediate constants for peak range.
	vec2 peakC = vec2(1.0, -1.0 * 4.0);

	// Limiters, these need to be high precision RCPs.
	float hitMinL = min(mn1L, e) / (4.0 * mx1L);
	float hitMaxL = (peakC.x - max(mx1L, e)) / (4.0 * mn1L + peakC.y);
	float lobeL = max(-hitMinL, hitMaxL);
	float lobe = max(float(-FSR_RCAS_LIMIT), min(lobeL, 0.0)) * exp2(-clamp(float(SHARPNESS), 0.0, 2.0));

	// Apply noise removal.
#if (FSR_RCAS_DENOISE == 1)
	// Noise detection.
	float nz = 0.25 * b + 0.25 * d + 0.25 * f + 0.25 * h - e;
	nz = clamp(abs(nz) * APrxMedRcpF1(AMax3F1(AMax3F1(b, d, e), f, h) - AMin3F1(AMin3F1(b, d, e), f, h)), 0.0, 1.0);
	nz = -0.5 * nz + 1.0;
	lobe *= nz;
#endif

	// Resolve, which needs the medium precision rcp approximation to avoid visible tonality changes.
	float rcpL = APrxMedRcpF1(4.0 * lobe + 1.0);
	vec4 pix = vec4(0.0, 0.0, 0.0, 1.0);
	pix.r = float((lobe * b + lobe * d + lobe * h + lobe * f + e) * rcpL);
#if (FSR_PQ == 1)
	pix.r = FromGamma2(pix.r);
#endif

	return pix;
}// MIT License

// Copyright (c) 2019-2021 bloc97
// All rights reserved.

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// Modified by Th-Underscore for FSR de-aliasing, darkening, and boundary protection

//!DESC Anime4K-v3.2-Thin-(HQ)-Luma
//!HOOK MAIN
//!BIND HOOKED
//!SAVE LINELUMA
//!COMPONENTS 1

float get_luma(vec4 rgba) {
	return dot(vec4(0.299, 0.587, 0.114, 0.0), rgba);
}

vec4 hook() {
	return vec4(get_luma(HOOKED_tex(HOOKED_pos)), 0.0, 0.0, 0.0);
}

//!DESC Anime4K-v3.2-Thin-(HQ)-Sobel-X
//!HOOK MAIN
//!BIND LINELUMA
//!SAVE LINESOBEL
//!COMPONENTS 2

vec4 hook() {
	float l = LINELUMA_texOff(vec2(-1.0, 0.0)).x;
	float c = LINELUMA_tex(LINELUMA_pos).x;
	float r = LINELUMA_texOff(vec2(1.0, 0.0)).x;

	float xgrad = (-l + r);
	float ygrad = (l + c + c + r);

	return vec4(xgrad, ygrad, 0.0, 0.0);
}


//!DESC Anime4K-v3.2-Thin-(HQ)-Sobel-Y
//!HOOK MAIN
//!BIND LINESOBEL
//!SAVE LINESOBEL
//!COMPONENTS 1

vec4 hook() {
	float tx = LINESOBEL_texOff(vec2(0.0, -1.0)).x;
	float cx = LINESOBEL_tex(LINESOBEL_pos).x;
	float bx = LINESOBEL_texOff(vec2(0.0, 1.0)).x;

	float ty = LINESOBEL_texOff(vec2(0.0, -1.0)).y;
	float by = LINESOBEL_texOff(vec2(0.0, 1.0)).y;

	float xgrad = (tx + cx + cx + bx) / 8.0;

	float ygrad = (-ty + by) / 8.0;

	//Computes the luminance's gradient
	float norm = sqrt(xgrad * xgrad + ygrad * ygrad);
	return vec4(pow(norm, 0.7));
}


//!DESC Anime4K-v3.2-Thin-(HQ)-Gaussian-X
//!HOOK MAIN
//!BIND HOOKED
//!BIND LINESOBEL
//!SAVE LINESOBEL
//!COMPONENTS 1

#define SPATIAL_SIGMA (3.0 * float(HOOKED_size.y) / 1080.0) //Spatial window size, must be a positive real number.

#define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).
#define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.

float gaussian(float x, float s, float m) {
	float scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float comp_gaussian_x() {

	float g = 0.0;
	float gn = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float di = float(i - KERNELHALFSIZE);
		float gf = gaussian(di, SPATIAL_SIGMA, 0.0);

		g = g + LINESOBEL_texOff(vec2(di, 0.0)).x * gf;
		gn = gn + gf;

	}

	return g / gn;
}

vec4 hook() {
	return vec4(comp_gaussian_x(), 0.0, 0.0, 0.0);
}


//!DESC Anime4K-v3.2-Thin-(HQ)-Gaussian-Y
//!HOOK MAIN
//!BIND HOOKED
//!BIND LINESOBEL
//!SAVE LINESOBEL
//!COMPONENTS 1

#define SPATIAL_SIGMA (3.0 * float(HOOKED_size.y) / 1080.0) //Spatial window size, must be a positive real number.

#define KERNELSIZE (max(int(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1) //Kernel size, must be an positive odd integer.
#define KERNELHALFSIZE (int(KERNELSIZE/2)) //Half of the kernel size without remainder. Must be equal to trunc(KERNELSIZE/2).
#define KERNELLEN (KERNELSIZE * KERNELSIZE) //Total area of kernel. Must be equal to KERNELSIZE * KERNELSIZE.

float gaussian(float x, float s, float m) {
	float scaled = (x - m) / s;
	return exp(-0.5 * scaled * scaled);
}

float comp_gaussian_y() {

	float g = 0.0;
	float gn = 0.0;

	for (int i=0; i<KERNELSIZE; i++) {
		float di = float(i - KERNELHALFSIZE);
		float gf = gaussian(di, SPATIAL_SIGMA, 0.0);

		g = g + LINESOBEL_texOff(vec2(0.0, di)).x * gf;
		gn = gn + gf;

	}

	return g / gn;
}

vec4 hook() {
	return vec4(comp_gaussian_y(), 0.0, 0.0, 0.0);
}

//!DESC Anime4K-v3.2-Thin-(HQ)-Kernel-X
//!HOOK MAIN
//!BIND LINESOBEL
//!SAVE LINESOBEL
//!COMPONENTS 3

vec4 hook() {
	float l = LINESOBEL_texOff(vec2(-1.0, 0.0)).x;
	float c = LINESOBEL_tex(LINESOBEL_pos).x;
	float r = LINESOBEL_texOff(vec2(1.0, 0.0)).x;

	float xgrad = (-l + r);
	float ygrad = (l + c + c + r);

	return vec4(xgrad, ygrad, c, 0.0);
}


//!DESC Anime4K-v3.2-Thin-(HQ)-Kernel-Y
//!HOOK MAIN
//!BIND LINESOBEL
//!SAVE LINESOBEL
//!COMPONENTS 3

vec4 hook() {
	float tx = LINESOBEL_texOff(vec2(0.0, -1.0)).x;
	float cx = LINESOBEL_tex(LINESOBEL_pos).x;
	float bx = LINESOBEL_texOff(vec2(0.0, 1.0)).x;

	float ty = LINESOBEL_texOff(vec2(0.0, -1.0)).y;
	float by = LINESOBEL_texOff(vec2(0.0, 1.0)).y;

	float xgrad = (tx + cx + cx + bx) / 8.0;
	float ygrad = (-ty + by) / 8.0;

	float line_mask = LINESOBEL_tex(LINESOBEL_pos).z;

	return vec4(xgrad, ygrad, line_mask, 0.0);
}

//!DESC Anime4K-v3.2-Thin-(HQ)-Warp
//!HOOK MAIN
//!BIND HOOKED
//!BIND LINESOBEL

#define STRENGTH 0.16 //Strength of warping for each iteration
#define ITERATIONS 3 //Number of iterations for the forwards solver, decreasing strength and increasing iterations improves quality at the cost of speed.

#define DARKEN_STRENGTH 0.8 // 0.0 to 1.0
#define MIN_LUMA 0.5        // Only darken pixels darker than this (0.0=black, 1.0=white)

float get_luma(vec4 rgba) {
	return dot(vec4(0.299, 0.587, 0.114, 0.0), rgba);
}

vec4 hook() {
	vec2 d = HOOKED_pt;
	float relstr = HOOKED_size.y / 1080.0 * STRENGTH;

	vec2 original_pos = HOOKED_pos;
	vec2 pos = original_pos;

    // Gradient vector for validation later
    vec2 gradient_vec = vec2(0.0);

	for (int i=0; i<ITERATIONS; i++) {
		vec2 dn = LINESOBEL_tex(pos).xy;
        if (i == 0) gradient_vec = dn; // Capture primary direction
		vec2 dd = (dn / (length(dn) + 0.01)) * d * relstr; //Quasi-normalization for large vectors, avoids divide by zero
		pos -= dd;
	}

	vec4 c = HOOKED_tex(pos);

	float line_intensity = LINESOBEL_tex(HOOKED_pos).z;
	float darken_mask = smoothstep(0.05, 0.4, line_intensity);

    // Find the perpendicular direction of the edge
    vec2 dir = normalize(gradient_vec + 0.0001) * HOOKED_pt * 1.5;

    float luma_center = get_luma(HOOKED_tex(original_pos));
    float luma_pos = get_luma(HOOKED_tex(original_pos + dir));
    float luma_neg = get_luma(HOOKED_tex(original_pos - dir));

    // Line = Luma is lower in center than both sides
    float diff_pos = luma_pos - luma_center;
    float diff_neg = luma_neg - luma_center;

    float is_valley = smoothstep(0.0, 0.05, diff_pos) * smoothstep(0.0, 0.05, diff_neg);
    darken_mask *= is_valley;

	float luma = get_luma(c);
	float darkness_weight = 1.0 - smoothstep(0.0, MIN_LUMA, luma);

	c.rgb -= c.rgb * darken_mask * darkness_weight * DARKEN_STRENGTH;
	return c;
}