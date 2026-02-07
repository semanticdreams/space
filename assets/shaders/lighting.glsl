#define MAX_DIR_LIGHTS 4
#define MAX_POINT_LIGHTS 8
#define MAX_SPOT_LIGHTS 4

struct DirLight {
    vec3 direction;

    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

struct PointLight {
    vec3 position;

    vec3 ambient;
    vec3 diffuse;
    vec3 specular;

    float constant;
    float linear;
    float quadratic;
};

struct SpotLight {
    vec3 position;
    vec3 direction;

    vec3 ambient;
    vec3 diffuse;
    vec3 specular;

    float cutOff;
    float outerCutOff;

    float constant;
    float linear;
    float quadratic;
};

float CalcAttenuation(float constant, float linear, float quadratic, float distance)
{
    return 1.0 / (constant + linear * distance + quadratic * (distance * distance));
}

vec3 CalcDirLight(DirLight light, vec3 normal, vec3 viewDir)
{
    vec3 lightDir = normalize(-light.direction);
    float diff = max(dot(normal, lightDir), 0.0);
    vec3 reflectDir = reflect(-lightDir, normal);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
    vec3 ambient  = light.ambient;
    vec3 diffuse  = light.diffuse  * diff;
    vec3 specular = light.specular * spec;
    return (ambient + diffuse + specular);
}

vec3 CalcPointLight(PointLight light, vec3 normal, vec3 fragPos, vec3 viewDir)
{
    vec3 lightDir = normalize(light.position - fragPos);
    float diff = max(dot(normal, lightDir), 0.0);
    vec3 reflectDir = reflect(-lightDir, normal);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
    float distance = length(light.position - fragPos);
    float attenuation = CalcAttenuation(light.constant, light.linear, light.quadratic, distance);
    vec3 ambient  = light.ambient  * attenuation;
    vec3 diffuse  = light.diffuse  * diff * attenuation;
    vec3 specular = light.specular * spec * attenuation;
    return (ambient + diffuse + specular);
}

vec3 CalcSpotLight(SpotLight light, vec3 normal, vec3 fragPos, vec3 viewDir)
{
    vec3 lightDir = normalize(light.position - fragPos);
    float diff = max(dot(normal, lightDir), 0.0);
    vec3 reflectDir = reflect(-lightDir, normal);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
    float distance = length(light.position - fragPos);
    float attenuation = CalcAttenuation(light.constant, light.linear, light.quadratic, distance);
    float theta = dot(lightDir, normalize(-light.direction));
    float epsilon = light.cutOff - light.outerCutOff;
    float intensity = clamp((theta - light.outerCutOff) / epsilon, 0.0, 1.0);
    vec3 ambient  = light.ambient  * attenuation * intensity;
    vec3 diffuse  = light.diffuse  * diff * attenuation * intensity;
    vec3 specular = light.specular * spec * attenuation * intensity;
    return (ambient + diffuse + specular);
}

vec3 CalcDirLights(DirLight lights[MAX_DIR_LIGHTS], int count, vec3 normal, vec3 viewDir)
{
    vec3 result = vec3(0.0);
    for (int i = 0; i < count; ++i) {
        result += CalcDirLight(lights[i], normal, viewDir);
    }
    return result;
}

vec3 CalcPointLights(PointLight lights[MAX_POINT_LIGHTS], int count, vec3 normal, vec3 fragPos, vec3 viewDir)
{
    vec3 result = vec3(0.0);
    for (int i = 0; i < count; ++i) {
        result += CalcPointLight(lights[i], normal, fragPos, viewDir);
    }
    return result;
}

vec3 CalcSpotLights(SpotLight lights[MAX_SPOT_LIGHTS], int count, vec3 normal, vec3 fragPos, vec3 viewDir)
{
    vec3 result = vec3(0.0);
    for (int i = 0; i < count; ++i) {
        result += CalcSpotLight(lights[i], normal, fragPos, viewDir);
    }
    return result;
}
