#version 330 core

in vec4 thePosition;
smooth in vec4 theColor;
flat in int depth_offset_index;
out vec4 fragColor;

const float depthStep = 1e-3;

struct DirLight {
    vec3 direction;
  
    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};  

vec3 CalcDirLight(DirLight light, vec3 normal, vec3 viewDir)
{
    vec3 lightDir = normalize(-light.direction);

    // Diffuse shading
    float diff = max(dot(normal, lightDir), 0.0);

    // Specular shading
    vec3 reflectDir = reflect(-lightDir, normal);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32); // 32 = material.shininess

    // Combine results
    vec3 ambient  = light.ambient; 
    vec3 diffuse  = light.diffuse  * diff;
    vec3 specular = light.specular * spec * 1.0f; // 0.5f = material.specular
    return (ambient + diffuse + specular);
}  

uniform vec3 viewPos;
uniform DirLight dirLight;

void main()
{  
	vec3 normal = normalize(cross(dFdy(thePosition.xyz), dFdx(thePosition.xyz)));
	vec3 viewDir = normalize(viewPos - thePosition.xyz);

	vec3 light = CalcDirLight(dirLight, normal, -viewDir);

	fragColor = vec4(light, 1.0f) * theColor;
	gl_FragDepth = max(0.0, gl_FragCoord.z - (gl_FragCoord.z * float(depth_offset_index) * depthStep));
}