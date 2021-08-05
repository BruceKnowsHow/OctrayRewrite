/*
====================================================================================================

        License Terms for Academy Color Encoding System Components

        Academy Color Encoding System (ACES) software and tools are provided by the
        Academy under the following terms and conditions: A worldwide, royalty-free,
        non-exclusive right to copy, modify, create derivatives, and use, in source and
        binary forms, is hereby granted, subject to acceptance of this license.

        Copyright © 2015 Academy of Motion Picture Arts and Sciences (A.M.P.A.S.).
        Portions contributed by others as indicated. All rights reserved.

        Performance of any of the aforementioned acts indicates acceptance to be bound
        by the following terms and conditions:

        * Copies of source code, in whole or in part, must retain the above copyright
        notice, this list of conditions and the Disclaimer of Warranty.

        * Use in binary form must retain the above copyright notice, this list of
        conditions and the Disclaimer of Warranty in the documentation and/or other
        materials provided with the distribution.

        * Nothing in this license shall be deemed to grant any rights to trademarks,
        copyrights, patents, trade secrets or any other intellectual property of
        A.M.P.A.S. or any contributors, except as expressly stated herein.

        * Neither the name "A.M.P.A.S." nor the name of any other contributors to this
        software may be used to endorse or promote products derivative of or based on
        this software without express prior written permission of A.M.P.A.S. or the
        contributors, as appropriate.

        This license shall be construed pursuant to the laws of the State of
        California, and any disputes related thereto shall be subject to the
        jurisdiction of the courts therein.

        Disclaimer of Warranty: THIS SOFTWARE IS PROVIDED BY A.M.P.A.S. AND CONTRIBUTORS
        "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
        THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
        NON-INFRINGEMENT ARE DISCLAIMED. IN NO EVENT SHALL A.M.P.A.S., OR ANY
        CONTRIBUTORS OR DISTRIBUTORS, BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
        SPECIAL, EXEMPLARY, RESITUTIONARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
        LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
        PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
        LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
        OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
        ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

        WITHOUT LIMITING THE GENERALITY OF THE FOREGOING, THE ACADEMY SPECIFICALLY
        DISCLAIMS ANY REPRESENTATIONS OR WARRANTIES WHATSOEVER RELATED TO PATENT OR
        OTHER INTELLECTUAL PROPERTY RIGHTS IN THE ACADEMY COLOR ENCODING SYSTEM, OR
        APPLICATIONS THEREOF, HELD BY PARTIES OTHER THAN A.M.P.A.S.,WHETHER DISCLOSED OR
        UNDISCLOSED.

====================================================================================================
*/
#undef AP1

const float pi = radians(180.0);
const float sqrPi = pi * pi;
const float halfPi = pi / 2.0;
const float rpi = 1.0 / pi;
const float pi4 = pi * 4.0;
const float tau = radians(360.0);
const float sqrt2 = sqrt(2.0);
const float sqrt3 = sqrt(3.0);
const float rLog10  = 1.0 / log(10.0);

#define rcp(x) (1.0 / (x))
#define min3(x, y, z) min(min(x, y), z)
#define max3(x, y, z) max(max(x, y), z)
#define cube(x) ((x) * (x) * (x))
#define sqr(x) ((x) * (x))
#define clamp16F(x) clamp(x, 0.0, 65535.0)
#define max0(x) max(0.0, x)
#define log10(x) (log(x) * rLog10)

#ifndef incACESMT
/* #include "transforms.glsl" */
#define incACESMT

/*
    Conversions between XYZ, AP0 and AP1
*/
const mat3 AP0_XYZ = mat3(
	0.9525523959, 0.0000000000, 0.0000936786,
	0.3439664498, 0.7281660966,-0.0721325464,
	0.0000000000, 0.0000000000, 1.0088251844
);
const mat3 XYZ_AP0 = mat3(
	 1.0498110175, 0.0000000000,-0.0000974845,
	-0.4959030231, 1.3733130458, 0.0982400361,
	 0.0000000000, 0.0000000000, 0.9912520182
);

const mat3 AP1_XYZ = mat3(
	 0.6624541811, 0.1340042065, 0.1561876870,
	 0.2722287168, 0.6740817658, 0.0536895174,
	-0.0055746495, 0.0040607335, 1.0103391003
);
const mat3 XYZ_AP1 = mat3(
	 1.6410233797, -0.3248032942, -0.2364246952,
	-0.6636628587,  1.6153315917,  0.0167563477,
	 0.0117218943, -0.0082844420,  0.9883948585
);

const mat3 AP0_AP1 = mat3(
	 1.4514393161, -0.2365107469, -0.2149285693,
	-0.0765537734,  1.1762296998, -0.0996759264,
	 0.0083161484, -0.0060324498,  0.9977163014
);
const mat3 AP1_AP0 = mat3(
	 0.6954522414,  0.1406786965,  0.1638690622,
	 0.0447945634,  0.8596711185,  0.0955343182,
	-0.0055258826,  0.0040252103,  1.0015006723
);

const vec3 AP1_RGB_Y = vec3(0.2722287168, 0.6740817658, 0.0536895174);

/*
    Rec709 primaries
*/
const mat3 XYZ_sRGB = mat3(
	 3.2409699419, -1.5373831776, -0.4986107603,
	-0.9692436363,  1.8759675015,  0.0415550574,
	 0.0556300797, -0.2039769589,  1.0569715142
);
const mat3 sRGB_XYZ = mat3(
	0.4124564, 0.3575761, 0.1804375,
	0.2126729, 0.7151522, 0.0721750,
	0.0193339, 0.1191920, 0.9503041
);

/* DCI P3, D65 primaries */
const mat3 XYZ_P3D65 = mat3(
	 2.4933963, -0.9313459, -0.4026945,
	-0.8294868,  1.7626597,  0.0236246,
	 0.0358507, -0.0761827,  0.9570140
);
const mat3 P3D65_XYZ = mat3(
	0.4865906, 0.2656683, 0.1981905,
	0.2289838, 0.6917402, 0.0792762,
	0.0000000, 0.0451135, 1.0438031
);

/*
    Bradford Chromatic Adaptation between ACES whitepoint (D60) and sRGB whitepoint (D65)
*/
const mat3 D65_D60 = mat3(
	 1.01303,    0.00610531, -0.014971,
	 0.00769823, 0.998165,   -0.00503203,
	-0.00284131, 0.00468516,  0.924507
);
const mat3 D60_D65 = mat3(
	 0.987224,   -0.00611327, 0.0159533,
	-0.00759836,  1.00186,    0.00533002,
	 0.00307257, -0.00509595, 1.08168
);

/*
    Conversions to and from sRGB
*/
const mat3 sRGB_AP0 = (sRGB_XYZ * D65_D60) * XYZ_AP0;
const mat3 sRGB_AP1 = (sRGB_XYZ * D65_D60) * XYZ_AP1;

const mat3 AP0_sRGB = (AP0_XYZ * D60_D65) * XYZ_sRGB;
const mat3 AP1_sRGB = (AP1_XYZ * D60_D65) * XYZ_sRGB;
/* End#include "transforms.glsl" */
#endif

/* #include "functions.glsl" */
vec3 greaterThanVec3(vec3 x, vec3 y, vec3 a, vec3 b) {
    vec3 data   = vec3(0.0);
        data.x  = x.x > y.x ? a.x : b.x;
        data.y  = x.y > y.y ? a.y : b.y;
        data.z  = x.z > y.z ? a.z : b.z;

    return data;
}
vec3 smallerThanVec3(vec3 x, vec3 y, vec3 a, vec3 b) {
    vec3 data   = vec3(0.0);
        data.x  = x.x < y.x ? a.x : b.x;
        data.y  = x.y < y.y ? a.y : b.y;
        data.z  = x.z < y.z ? a.z : b.z;

    return data;
}

#define saturate(x) clamp(x, 0.0, 1.0)

float rgbSaturation(vec3 rgb) {
    float minrgb    = min3(rgb.x, rgb.y, rgb.z);
    float maxrgb    = max3(rgb.x, rgb.y, rgb.z);

    return (max(maxrgb, 1e-10) - max(minrgb, 1e-10)) / max(maxrgb, 1e-2);
}

float glowFwd(float ycIn, float glowGainIn, float glowMid) {
    if (ycIn <= 2.0 / 3.0 * glowMid) return glowGainIn;
    else if (ycIn >= 2.0 * glowMid) return 0.0;
    else return glowGainIn * (glowMid / ycIn - 0.5);
}

/* geometric hue angle calculation */
float rgbHue(vec3 rgb) {
    float hue;
    if (rgb.x == rgb.y && rgb.y == rgb.z) hue = 0.0;
    else hue = (180.0 * rcp(pi)) * atan(2.0 * rgb.x - rgb.y - rgb.z, sqrt(3.0) * (rgb.y - rgb.z));

    if (hue < 0.0) hue = hue + 360.0;

    return clamp(hue, 0.0, 360.0);
}

float rgbYC1(vec3 rgb, const float ycRadweight) {
    float chroma    = sqrt(rgb.b * (rgb.b - rgb.g) + rgb.g * (rgb.g - rgb.r) + rgb.r * (rgb.r - rgb.b));

    return (rgb.b + rgb.g + rgb.r + ycRadweight * chroma) * rcp(3.0);
}
float rgbYC(vec3 rgb) {
    return rgbYC1(rgb, 1.75);
}

float centerHue(float hue, float center) {
    float hueCentered = hue - center;

    if (hueCentered < -180.0) hueCentered += 360.0;
    else if (hueCentered > 180.0) hueCentered -= 360.0;

    return hueCentered;
}

float y_linVC(float y, float max, float min) {
    return (y - min) / (max - min);
}

vec3 XYZ_xyY(vec3 xyz) {
    vec3 xyY;
    float divisor   = (xyz.r + xyz.g + xyz.b);

    if (divisor == 0.0) divisor = 1e-10;
    xyY.r   = xyz.r / divisor;
    xyY.g   = xyz.g / divisor;
    xyY.b   = xyz.g;

    return xyY;
}
vec3 xyY_XYZ(vec3 xyY) {
    vec3 xyz;

    xyz.r   = xyY.x * xyY.z / max(xyY.g, 1e-10);
    xyz.g   = xyY.z;
    xyz.b   = (1.0 - xyY.x - xyY.y) * xyY.z / max(xyY.y, 1e-10);

    return xyz;
}
/* End #include "functions.glsl" */


/* Spline.glsl */
/*
    Sigmoid function in the range of 0 - 1 spanning to -2 - +2
*/
float sigmoidShaper(float x) {
    float t     = max(1.0 - abs(0.5 * x), 0);
    float y     = 1.0 + sign(x) * (1.0 - sqr(t));

    return 0.5 * y;
}

float cubicBasisShaper(float x, float w) {

    const vec4 MAT[4] = vec4[4](
        vec4( -1.0 / 6.0,  3.0 / 6.0, -3.0 / 6.0,  1.0 / 6.0),
        vec4(  3.0 / 6.0, -6.0 / 6.0,  3.0 / 6.0,  0.0 / 6.0), 
        vec4( -3.0 / 6.0,  0.0 / 6.0,  3.0 / 6.0,  0.0 / 6.0), 
        vec4(  1.0 / 6.0,  4.0 / 6.0,  1.0 / 6.0,  0.0 / 6.0)
    );

    float knot[5] = float[5](
        -0.5 * w,
        -0.25 * w,
        0.0, 
        0.25 * w,
        0.5 * w
    );

    float y     = 0.0;

    if ((x > knot[0]) && (x < knot[4])) {
        float knotCoord    = (x - knot[0]) * 4.0 * rcp(w);

        int j   = int(knotCoord);
        float t = knotCoord - j;

        float monomials[4]  = float[4](
            cube(t),
            sqr(t),
            t,
            1.0
        );

        /* this section can be simplified */
        if (j == 3) {
            y   = monomials[0] * MAT[0].x + monomials[1] * MAT[1].x
                + monomials[2] * MAT[2].x + monomials[3] * MAT[3].x;
        } else if (j == 2) {
            y   = monomials[0] * MAT[0].y + monomials[1] * MAT[1].y
                + monomials[2] * MAT[2].y + monomials[3] * MAT[3].y;
        } else if (j == 1) {
            y   = monomials[0] * MAT[0].z + monomials[1] * MAT[1].z
                + monomials[2] * MAT[2].z + monomials[3] * MAT[3].z;
        } else if (j == 0) {
            y   = monomials[0] * MAT[0].w + monomials[1] * MAT[1].w
                + monomials[2] * MAT[2].w + monomials[3] * MAT[3].w;
        } else {
            y   = 0.0;
        }
    }

    return y * 1.5;
}

const mat3 MAT = mat3(
    0.5, -1.0, 0.5,
    -1.0, 1.0, 0.5, 
    0.5, 0.0, 0.0
);

struct segmentedSplineParamC5 {
    float coeffLow[6];
    float coeffHigh[6];
    vec2 minPoint;
    vec2 midPoint;
    vec2 maxPoint;
    float slopeLow;
    float slopeHigh;
};

float segmentedSplineC5Fwd(float x) {
    /* RRT Parameters */
    const segmentedSplineParamC5 c = segmentedSplineParamC5(
        float[6](-4.0, -4.0, -3.1573765773, -0.4852499958, 1.8477324706, 1.8477324706), 
        float[6](-0.7185482425, 2.0810307172, 3.6681241237, 4.0, 4.0, 4.0),
        vec2(0.18 * exp2(-15.0), 0.0001),
        vec2(0.18, 4.8),
        vec2(0.18 * exp2(18.0), 10000.0),
        0.0,
        0.0
    );

    const int N_KNOTS_LOW   = 4;
    const int N_KNOTS_HIGH  = 4;

    float x_check = x <= 0.0 ? exp2(-14.0) : x;

    float logx  = log10(x_check);
    float logy;

    if (logx <= log10(c.minPoint.x)) {
        logy    = logx * c.slopeLow + (log10(c.minPoint.y) - c.slopeLow * log10(c.minPoint.x));
    } else if ((logx > log10(c.minPoint.x)) && (logx < log10(c.midPoint.x))) {
        float knotCoord = (N_KNOTS_LOW - 1) * (logx - log10(c.minPoint.x)) * rcp(log10(c.midPoint.x) - log10(c.minPoint.x));
        int j   = int(knotCoord);
        float t = knotCoord - j;

        vec3 cf = vec3(c.coeffLow[j], c.coeffLow[j+1], c.coeffLow[j+2]);

        vec3 monomials = vec3(sqr(t), t, 1.0);

        logy    = dot(monomials, MAT * cf);
    } else if ((logx >= log10(c.midPoint.x)) && (logx < log10(c.maxPoint.x))) {
        float knotCoord = (N_KNOTS_HIGH - 1) * (logx - log10(c.midPoint.x)) * rcp(log10(c.maxPoint.x) - log10(c.midPoint.x));
        int j   = int(knotCoord);
        float t = knotCoord - j;

        vec3 cf = vec3(c.coeffHigh[j], c.coeffHigh[j+1], c.coeffHigh[j+2]);

        vec3 monomials = vec3(sqr(t), t, 1.0);

        logy    = dot(monomials, MAT * cf);
    } else {
        logy    = logx * c.slopeHigh + (log10(c.maxPoint.y) - c.slopeHigh * log10(c.maxPoint.x));
    }
    return pow(10.0, logy);
}

struct segmentedSplineParamC9 {
    float coeffLow[10];
    float coeffHigh[10];
    vec2 minPoint;
    vec2 midPoint;
    vec2 maxPoint;
    float slopeLow;
    float slopeHigh;
};

float segmentedSplineC9Fwd(float x, const segmentedSplineParamC9 c) {
    const int N_KNOTS_LOW   = 8;
    const int N_KNOTS_HIGH  = 8;

    float x_check = x <= 0.0 ? 1e-4 : x;

    float logx  = log10(x_check);
    float logy;

    if (logx <= log10(c.minPoint.x)) {
        logy    = logx * c.slopeLow + (log10(c.minPoint.y) - c.slopeLow * log10(c.minPoint.x));
    } else if ((logx > log10(c.minPoint.x)) && (logx < log10(c.midPoint.x))) {
        float knotCoord = (N_KNOTS_LOW - 1) * (logx - log10(c.minPoint.x)) * rcp(log10(c.midPoint.x) - log10(c.minPoint.x));
        int j   = int(knotCoord);
        float t = knotCoord - j;

        vec3 cf = vec3(c.coeffLow[j], c.coeffLow[j+1], c.coeffLow[j+2]);

        vec3 monomials = vec3(sqr(t), t, 1.0);

        logy    = dot(monomials, MAT * cf);
    } else if ((logx >= log10(c.midPoint.x)) && (logx < log10(c.maxPoint.x))) {
        float knotCoord = (N_KNOTS_HIGH - 1) * (logx - log10(c.midPoint.x)) * rcp(log10(c.maxPoint.x) - log10(c.midPoint.x));
        int j   = int(knotCoord);
        float t = knotCoord - j;

        vec3 cf = vec3(c.coeffHigh[j], c.coeffHigh[j+1], c.coeffHigh[j+2]);

        vec3 monomials = vec3(sqr(t), t, 1.0);

        logy    = dot(monomials, MAT * cf);
    } else {
        logy    = logx * c.slopeHigh + (log10(c.maxPoint.y) - c.slopeHigh * log10(c.maxPoint.x));
    }
    return pow(10.0, logy);
}
/* End Spline.glsl */

/*
    This is directly based off the reference implementation of the
    Reference Rendering Transform given by the academy on https://github.com/ampas/aces-dev
    Equivalent Reference Revision: 1.2
*/

#define acesRRTExposureBias 1.00    //[0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50]
#define acesRRTGammaLift 1.00       //[0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50]
#define acesRRTGlowGainOffset 0.0   //[-0.20 -0.18 -0.16 -0.14 -0.12 -0.10 -0.08 -0.06 -0.04 -0.02 0.0 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20]
#define acesRRTSatOffset 0.0        //[-0.20 -0.18 -0.16 -0.14 -0.12 -0.10 -0.08 -0.06 -0.04 -0.02 0.0 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20]
#define acesODTSatOffset 0.0        //[-0.20 -0.18 -0.16 -0.14 -0.12 -0.10 -0.08 -0.06 -0.04 -0.02 0.0 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20]

const float dimSurroundGamma = 0.911; //Academy Default 0.9811

const float rrtGlowGain     = 0.20 + acesRRTGlowGainOffset;     //Academy Default 0.05, Neutral Default 0.28
const float rrtGlowMid      = 0.08;     //default 0.08

const float rrtRedScale     = 0.96;     //Academy Default 0.82, Neutral Default 1.0
const float rrtRedPrivot    = 0.03;     //Academy Default 0.03
const float rrtRedHue       = 0.00;     //Academy Default 0.0
const float rrtRedWidth     = 135.0;    //Academy Default 135.0

const float rrtSatFactor    = 1.00 + acesRRTSatOffset;      //default 0.96
const float rrtGammaLift    = 0.85 / acesRRTGammaLift;      //Default 1.00
const float odtSatFactor    = 0.98 + acesODTSatOffset;      //default 0.93

vec3 darkToDimSurround(vec3 linearCV) {
    vec3 XYZ    = linearCV * AP1_XYZ;
    vec3 xyY    = XYZ_xyY(XYZ);
        xyY.z   = clamp(xyY.z, 0.0, 65535.0);
        xyY.z   = pow(xyY.z, dimSurroundGamma);
        XYZ     = xyY_XYZ(xyY);

    return XYZ * XYZ_AP1;
}

mat3x3 calcSaturationMatrix(const float sat, const vec3 rgb_y) {
    mat3x3 M;
        M[0].r = (1.0 - sat) * rgb_y.r + sat;
        M[1].r = (1.0 - sat) * rgb_y.r;
        M[2].r = (1.0 - sat) * rgb_y.r;

        M[0].g = (1.0 - sat) * rgb_y.g;
        M[1].g = (1.0 - sat) * rgb_y.g + sat;
        M[2].g = (1.0 - sat) * rgb_y.g;

        M[0].b = (1.0 - sat) * rgb_y.b;
        M[1].b = (1.0 - sat) * rgb_y.b;
        M[2].b = (1.0 - sat) * rgb_y.b + sat;

    return M;
}

vec3 rrtSweeteners(vec3 ACES2065) {
    /* Glow module */
    float saturation    = rgbSaturation(ACES2065);
    float ycIn          = rgbYC(ACES2065);
    float s             = sigmoidShaper((saturation - 0.4) * rcp(0.2));
    float addedGlow     = 1.0 + glowFwd(ycIn, rrtGlowGain * s, rrtGlowMid);
    
        ACES2065       *= addedGlow;

    /* Red Modifier module */
    float hue           = rgbHue(ACES2065);
    float centeredHue   = centerHue(hue, rrtRedHue);
    float hueWeight     = cubicBasisShaper(centeredHue, rrtRedWidth);

        ACES2065.r     += hueWeight * saturation * (rrtRedPrivot - ACES2065.r) * (1.0 - rrtRedScale);

    /* Transform AP0 ACES2065-1 to AP1 ACEScg */
        ACES2065        = clamp(ACES2065, 0.0, 65535.0);

    vec3 ACEScg         = ACES2065 * AP0_AP1;
        ACEScg          = clamp(ACEScg, 0.0, 65535.0);

    /* Global Desaturation */
        ACEScg          = mix(vec3(dot(ACEScg, AP1_RGB_Y)), ACEScg, rrtSatFactor);

    /* Added Gamma Correction to allow for color response tuning before mapping to LDR */
        ACEScg          = pow(ACEScg, vec3(rrtGammaLift));
    
    return ACEScg;
}

/* takes input as academy color and returns oces */
vec3 academyRRT(vec3 ACES2065) {
    vec3 ACEScgIn       = ACES2065;

    /* Apply tonescale in AP1 ACEScg */
    vec3 ACEScgOut;
        ACEScgOut.r     = segmentedSplineC5Fwd(ACEScgIn.r);
        ACEScgOut.g     = segmentedSplineC5Fwd(ACEScgIn.g);
        ACEScgOut.b     = segmentedSplineC5Fwd(ACEScgIn.b);

    /* Transform AP1 ACEScg back to AP0 ACES2065-1 */
    return ACEScgOut * AP1_AP0;
}

vec3 odtSRGB_D65(vec3 ACES2065) {
    /* Transform AP0 ACES2065-1 to AP1 ACEScg */
    vec3 ACEScgIn   = ACES2065 * AP0_AP1;

    segmentedSplineParamC9 odt_48nit = segmentedSplineParamC9(
        float[10](-1.6989700043, -1.6989700043, -1.4779000000, -1.2291000000, -0.8648000000, -0.4480000000, 0.0051800000, 0.4511080334, 0.9113744414, 0.9113744414),
        float[10](0.5154386965, 0.8470437783, 1.1358000000, 1.3802000000, 1.5197000000, 1.5985000000, 1.6467000000, 1.6746091357, 1.6878733390, 1.6878733390),
        vec2(segmentedSplineC5Fwd(0.18 * exp2(-6.5)), 0.02),
        vec2(segmentedSplineC5Fwd(0.18), 4.8),
        vec2(segmentedSplineC5Fwd(0.18 * exp2(6.5)), 48.0),
        0.0,
        0.04
    );

    /* Apply tonescale in AP1 ACEScg */
    vec3 ACEScgOut;
        ACEScgOut.r     = segmentedSplineC9Fwd(ACEScgIn.r, odt_48nit);
        ACEScgOut.g     = segmentedSplineC9Fwd(ACEScgIn.g, odt_48nit);
        ACEScgOut.b     = segmentedSplineC9Fwd(ACEScgIn.b, odt_48nit);

    /* Black and White points for cinema system */
    const float cinemaWhite    = 48.0;
    const float cinemaBlack    = 0.02;     //white / 2400.0, default 0.02

    /* Scale Luminance to linear relative to the Black and White Points */
    vec3 linearCV;
        linearCV.r      = y_linVC(ACEScgOut.r, cinemaWhite, cinemaBlack);
        linearCV.g      = y_linVC(ACEScgOut.g, cinemaWhite, cinemaBlack);
        linearCV.b      = y_linVC(ACEScgOut.b, cinemaWhite, cinemaBlack);

        linearCV        = darkToDimSurround(linearCV);

    /* Global Desaturation */
        linearCV        = mix(vec3(dot(linearCV, AP1_RGB_Y)), linearCV, odtSatFactor);

    /* Convert to Display Primary Encoding */
    vec3 XYZ            = linearCV * AP1_XYZ;
        XYZ             = XYZ * D60_D65;

        linearCV        = XYZ * XYZ_sRGB;

    /* As we are now in our target Display Colorspace it can be assumed that values below 0.0 or above 1.0 are clipped */
    return saturate(linearCV);
}

/*
    This is an approximated version of the Reference Rendering Transform (RRT) in order
    to reduce the performance cost in realtime applications.
    Based on Epic Games' implementation using a piecewise filmic tonemapper in Unreal Engine 4.
*/

struct acesSplineFitParam {
    float slope;
    float toe;
    float shoulder;
    float blackClip;
    float whiteClip;
};

vec3 academySplineFit(vec3 rgbPre, const acesSplineFitParam curve) {
    #if (defined MC_GL_RENDERER_INTEL || defined MC_GL_RENDERER_MESA)
        float toeScale   = 1.0 + curve.blackClip - curve.toe;
        float shoulderScale = 1.0 + curve.whiteClip - curve.shoulder;
    #else
        const float toeScale   = 1.0 + curve.blackClip - curve.toe;
        const float shoulderScale = 1.0 + curve.whiteClip - curve.shoulder;
    #endif

    const float inMatch    = 0.18;
    const float outMatch   = 0.18;

    float toeMatch = 0.0;

    if (curve.toe > 0.8) {
        //0.18 on straight segment
        toeMatch   = (1.0 - curve.toe - outMatch) / curve.slope + log10(inMatch);
    } else {
        //0.18 on toe segment
        #if (defined MC_GL_RENDERER_INTEL || defined MC_GL_RENDERER_MESA)
            float bt  = (outMatch + curve.blackClip) / toeScale - 1.0;
        #else
            const float bt  = (outMatch + curve.blackClip) / toeScale - 1.0;
        #endif
        
        toeMatch   = log10(inMatch) - 0.5 * log((1.0 + bt) * rcp(1.0 - bt)) * (toeScale * rcp(curve.slope));
    }

    float straightMatch    = (1.0 - curve.toe) / curve.slope - toeMatch;
    float shoulderMatch    = curve.shoulder / curve.slope - straightMatch;

    vec3 logColor          = log10(rgbPre);
    vec3 straightColor     = curve.slope * (logColor + straightMatch);

    vec3 toeColor          = (     -curve.blackClip) + (2.0 * toeScale)      * rcp(1.0 + exp((-2.0 * curve.slope / toeScale)      * (logColor - toeMatch)));
    vec3 shoulderColor     = (1.0 + curve.whiteClip) - (2.0 * shoulderScale) * rcp(1.0 + exp(( 2.0 * curve.slope / shoulderScale) * (logColor - shoulderMatch)));

        toeColor           = smallerThanVec3(logColor, vec3(toeMatch), toeColor, straightColor);
        shoulderColor      = greaterThanVec3(logColor, vec3(shoulderMatch), shoulderColor, straightColor);

    vec3 t      = saturate((logColor - toeMatch) * rcp(shoulderMatch - toeMatch));
        t       = shoulderMatch < toeMatch ? 1.0 - t : t;
        t       = (3.0 - 2.0 * t) * t * t;

    return mix(toeColor, shoulderColor, t);
}

vec3 academyApprox(vec3 ACES2065) {
    vec3 rgbPre         = rrtSweeteners(ACES2065);

    const acesSplineFitParam curve = acesSplineFitParam(
        0.91,
        0.51,
        0.23,
        0.0,
        0.035
    );

    vec3 mappedColor    = academySplineFit(rgbPre, curve);

    /* Global Desaturation as it would be done in the Output Device Transform (ODT) otherwise */
        mappedColor     = mix(vec3(dot(mappedColor, AP1_RGB_Y)), mappedColor, odtSatFactor);
        mappedColor     = clamp16F(mappedColor);

    return mappedColor * AP1_AP0;
}

vec3 LinearToSRGB(vec3 x){
    return mix(max(vec3(0.0), x * 12.92), clamp16F(pow(x, vec3(1./2.4)) * 1.055 - 0.055), step(0.0031308, x));
}



/*
    Packed ACES transforms.
    First pair is for linear sRGB input, second pair for ACEScg input.
*/
vec3 ACES_LINEAR_SRGB_RRT(vec3 LIN) {
        LIN    *= 1.313 * acesRRTExposureBias;
    vec3 ACES   = LIN * sRGB_AP0;
        ACES    = academyRRT(ACES);
        ACES    = odtSRGB_D65(ACES);

    return LinearToSRGB(ACES);
}
vec3 ACES_LINEAR_SRGB(vec3 LIN) {
        LIN    *= acesRRTExposureBias;
    vec3 ACES   = LIN * sRGB_AP0;
        ACES    = academyApprox(ACES);
        ACES    = ACES * AP0_sRGB;

    return LinearToSRGB(ACES);
}

vec3 ACES_AP1_SRGB_RRT(vec3 AP1) {
        AP1    *= acesRRTExposureBias;
    vec3 ACES   = AP1 * AP1_AP0;
        ACES    = academyRRT(ACES);
        ACES    = odtSRGB_D65(ACES);

    return ACES;//LinearToSRGB(ACES);
}
vec3 ACES_AP1_SRGB(vec3 AP1) {
        AP1    *= acesRRTExposureBias;
    vec3 ACES   = AP1 * AP1_AP0;
        ACES    = academyApprox(ACES);
        ACES    = ACES * AP0_sRGB;

    return LinearToSRGB(ACES);
}


