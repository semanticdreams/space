#pragma once

#include <map>
#include <string>

#include <glm/glm.hpp>

struct Ciecam02Surround {
    float F;
    float c;
    float N_c;
};

struct Ciecam02Space {
    glm::vec3 XYZ100_w;
    float Y_b;
    float L_A;
    Ciecam02Surround surround;
};

struct Ciecam02Correlates {
    float J;
    float C;
    float h;
    float Q;
    float M;
    float s;
    float H;
};

struct LuoEtAl2006UniformSpace {
    float KL;
    float c1;
    float c2;
};

Ciecam02Surround ciecam02SurroundAverage();
Ciecam02Surround ciecam02SurroundDim();
Ciecam02Surround ciecam02SurroundDark();
Ciecam02Space ciecam02SpaceSrgb();

Ciecam02Correlates xyz100ToCiecam02(const glm::vec3& xyz100, const Ciecam02Space& space,
                                    const std::string& onNegativeA = "raise");
glm::vec3 ciecam02ToXyz100(const Ciecam02Space& space, const std::map<std::string, float>& correlates);

glm::mat3 machadoEtAl2009Matrix(const std::string& cvdType, float severity);
glm::vec3 applyMatrix3x3(const glm::mat3& matrix, const glm::vec3& value);

glm::vec3 jmhToJab(const glm::vec3& jmh, const LuoEtAl2006UniformSpace& space);
glm::vec3 jabToJmh(const glm::vec3& jab, const LuoEtAl2006UniformSpace& space);
LuoEtAl2006UniformSpace cam02UcsSpace();
LuoEtAl2006UniformSpace cam02LcdSpace();
LuoEtAl2006UniformSpace cam02ScdSpace();
