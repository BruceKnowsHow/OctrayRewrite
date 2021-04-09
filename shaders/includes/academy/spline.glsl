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

/*
    Sigmoid function in the range of 0 - 1 spanning to -2 - +2
*/
float sigmoidShaper(float x) {
    float t     = max(1.0 - abs(0.5 * x), 0);
    float y     = 1.0 + sign(x) * (1.0 - sqr(t));

    return 0.5 * y;
}

float cubicBasisShaper(float x, float w) {

    const vec4 M[4] = vec4[4](
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
            y   = monomials[0] * M[0].x + monomials[1] * M[1].x
                + monomials[2] * M[2].x + monomials[3] * M[3].x;
        } else if (j == 2) {
            y   = monomials[0] * M[0].y + monomials[1] * M[1].y
                + monomials[2] * M[2].y + monomials[3] * M[3].y;
        } else if (j == 1) {
            y   = monomials[0] * M[0].z + monomials[1] * M[1].z
                + monomials[2] * M[2].z + monomials[3] * M[3].z;
        } else if (j == 0) {
            y   = monomials[0] * M[0].w + monomials[1] * M[1].w
                + monomials[2] * M[2].w + monomials[3] * M[3].w;
        } else {
            y   = 0.0;
        }
    }

    return y * 1.5;
}

const mat3 M = mat3(
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

        logy    = dot(monomials, M * cf);
    } else if ((logx >= log10(c.midPoint.x)) && (logx < log10(c.maxPoint.x))) {
        float knotCoord = (N_KNOTS_HIGH - 1) * (logx - log10(c.midPoint.x)) * rcp(log10(c.maxPoint.x) - log10(c.midPoint.x));
        int j   = int(knotCoord);
        float t = knotCoord - j;

        vec3 cf = vec3(c.coeffHigh[j], c.coeffHigh[j+1], c.coeffHigh[j+2]);

        vec3 monomials = vec3(sqr(t), t, 1.0);

        logy    = dot(monomials, M * cf);
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

        logy    = dot(monomials, M * cf);
    } else if ((logx >= log10(c.midPoint.x)) && (logx < log10(c.maxPoint.x))) {
        float knotCoord = (N_KNOTS_HIGH - 1) * (logx - log10(c.midPoint.x)) * rcp(log10(c.maxPoint.x) - log10(c.midPoint.x));
        int j   = int(knotCoord);
        float t = knotCoord - j;

        vec3 cf = vec3(c.coeffHigh[j], c.coeffHigh[j+1], c.coeffHigh[j+2]);

        vec3 monomials = vec3(sqr(t), t, 1.0);

        logy    = dot(monomials, M * cf);
    } else {
        logy    = logx * c.slopeHigh + (log10(c.maxPoint.y) - c.slopeHigh * log10(c.maxPoint.x));
    }
    return pow(10.0, logy);
}