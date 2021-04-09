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
    #include "transforms.glsl"
#endif

#include "functions.glsl"
#include "spline.glsl"

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
    // vec3 ACEScgIn       = rrtSweeteners(ACES2065);
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
        AP1    *= 1.313 * acesRRTExposureBias;
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


