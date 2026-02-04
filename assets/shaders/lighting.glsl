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
