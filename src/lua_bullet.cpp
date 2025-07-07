#include <sol/sol.hpp>
#include <btBulletDynamicsCommon.h>
#include <BulletSoftBody/btSoftRigidDynamicsWorld.h>
#include <BulletSoftBody/btSoftBodyHelpers.h>

void lua_bind_bullet(sol::state& lua) {
    sol::table bt = lua.create_named_table("bt");

    bt.new_usertype<btVector3>("Vector3",
        sol::constructors<btVector3(), btVector3(float, float, float)>(),
        "x", sol::property(&btVector3::getX, &btVector3::setX),
        "y", sol::property(&btVector3::getY, &btVector3::setY),
        "z", sol::property(&btVector3::getZ, &btVector3::setZ),
        "length", &btVector3::length,
        "normalize", &btVector3::normalize
    );

    bt.new_usertype<btQuaternion>("Quaternion",
        sol::constructors<btQuaternion(), btQuaternion(float, float, float, float)>(),
        "x", &btQuaternion::getX,
        "y", &btQuaternion::getY,
        "z", &btQuaternion::getZ,
        "w", &btQuaternion::getW,
        "normalize", &btQuaternion::normalize
    );

}
