#include <sol/sol.hpp>
#include <memory>
#include <vector>
#include <stdexcept>
#include <BulletCollision/CollisionShapes/btBvhTriangleMeshShape.h>
#include <BulletCollision/CollisionShapes/btBoxShape.h>
#include <BulletCollision/CollisionShapes/btStaticPlaneShape.h>
#include <BulletCollision/CollisionShapes/btTriangleMesh.h>
#include <btBulletDynamicsCommon.h>
#include <BulletSoftBody/btSoftRigidDynamicsWorld.h>
#include <BulletSoftBody/btSoftBodyHelpers.h>
#include <BulletDynamics/Vehicle/btRaycastVehicle.h>
#include <BulletDynamics/Vehicle/btVehicleRaycaster.h>

#include "physics.h"

namespace {

sol::table create_physics_table(sol::state_view lua)
{
    sol::table bt = lua.create_table();

    bt.set_function("Scalar", [](float value) { return value; });

    bt.new_usertype<btVector3>("Vector3",
        sol::no_constructor,
        "x", sol::property(&btVector3::getX, &btVector3::setX),
        "y", sol::property(&btVector3::getY, &btVector3::setY),
        "z", sol::property(&btVector3::getZ, &btVector3::setZ),
        "length", &btVector3::length,
        "normalize", &btVector3::normalize,
        "setX", &btVector3::setX,
        "setY", &btVector3::setY,
        "setZ", &btVector3::setZ,
        "getX", &btVector3::getX,
        "getY", &btVector3::getY,
        "getZ", &btVector3::getZ
    );

    bt.new_usertype<btQuaternion>("Quaternion",
        sol::no_constructor,
        "x", &btQuaternion::getX,
        "y", &btQuaternion::getY,
        "z", &btQuaternion::getZ,
        "w", &btQuaternion::getW,
        "normalize", &btQuaternion::normalize
    );

    bt.new_usertype<btTransform>("Transform",
        sol::no_constructor,
        "setIdentity", &btTransform::setIdentity,
        "setOrigin", &btTransform::setOrigin,
        "getOrigin", [](btTransform& self) { return self.getOrigin(); },
        "setRotation", &btTransform::setRotation,
        "getRotation", [](btTransform& self) { return self.getRotation(); },
        "inverse", &btTransform::inverse
    );

    bt.new_usertype<btCollisionShape>("CollisionShape",
        "getName", &btCollisionShape::getName,
        "getShapeType", &btCollisionShape::getShapeType
    );

    bt.new_usertype<btTriangleMesh>("TriangleMesh",
        sol::no_constructor,
        "addTriangle", sol::overload(
            [](btTriangleMesh& self, const btVector3& v0, const btVector3& v1, const btVector3& v2) {
                self.addTriangle(v0, v1, v2, false);
            },
            [](btTriangleMesh& self, const btVector3& v0, const btVector3& v1, const btVector3& v2, bool removeDuplicateVertices) {
                self.addTriangle(v0, v1, v2, removeDuplicateVertices);
            })
    );

    bt.new_usertype<btBvhTriangleMeshShape>("BvhTriangleMeshShape",
        sol::no_constructor,
        sol::base_classes, sol::bases<btCollisionShape>()
    );

    bt.new_usertype<btStaticPlaneShape>("StaticPlaneShape",
        sol::no_constructor,
        sol::base_classes, sol::bases<btCollisionShape>()
    );

    bt.new_usertype<btBoxShape>("BoxShape",
        sol::no_constructor,
        "setLocalScaling", [](btBoxShape& self, const btVector3& scaling) {
            self.setLocalScaling(scaling);
        },
        "calculateLocalInertia", [](btBoxShape& self, btScalar mass, btVector3& inertia) {
            self.calculateLocalInertia(mass, inertia);
        },
        "getLocalScaling", [](btBoxShape& self) {
            return self.getLocalScaling();
        },
        sol::base_classes, sol::bases<btCollisionShape>()
    );

    bt.new_usertype<btMotionState>("MotionState",
        "getWorldTransform", [](btMotionState& self) {
            btTransform transform;
            self.getWorldTransform(transform);
            return transform;
        }
    );

    bt.new_usertype<btDefaultMotionState>("DefaultMotionState",
        sol::no_constructor,
        "getWorldTransform", [](btDefaultMotionState& self) {
            btTransform transform;
            self.getWorldTransform(transform);
            return transform;
        },
        "setWorldTransform", &btDefaultMotionState::setWorldTransform,
        sol::base_classes, sol::bases<btMotionState>()
    );

    using RigidBodyCI = btRigidBody::btRigidBodyConstructionInfo;
    bt.new_usertype<RigidBodyCI>("RigidBodyConstructionInfo",
        sol::no_constructor,
        "m-mass", &RigidBodyCI::m_mass,
        "m-motionState", &RigidBodyCI::m_motionState,
        "m-collisionShape", &RigidBodyCI::m_collisionShape,
        "m-localInertia", &RigidBodyCI::m_localInertia
    );

    bt.new_usertype<btRigidBody>("RigidBody",
        sol::no_constructor,
        "getMotionState", [](btRigidBody& self) {
            return self.getMotionState();
        },
        "setMotionState", &btRigidBody::setMotionState,
        "setWorldTransform", &btRigidBody::setWorldTransform,
        "getWorldTransform", [](btRigidBody& self) {
            return btTransform(self.getWorldTransform());
        },
        "getCenterOfMassTransform", [](btRigidBody& self) {
            return btTransform(self.getCenterOfMassTransform());
        },
        "setMassProps", &btRigidBody::setMassProps,
        "setLinearVelocity", &btRigidBody::setLinearVelocity,
        "setFriction", &btRigidBody::setFriction,
        "setRollingFriction", &btRigidBody::setRollingFriction,
        "setRestitution", &btRigidBody::setRestitution,
        "getLinearVelocity", [](btRigidBody& self) {
            return self.getLinearVelocity();
        },
        "applyForce", &btRigidBody::applyCentralForce,
        "setPosition", &btRigidBody::setWorldTransform,
        "getPosition", [](btRigidBody& self) {
            return btTransform(self.getWorldTransform());
        }
    );

    bt.new_usertype<btCollisionConfiguration>("CollisionConfiguration");

    bt.new_usertype<btDefaultCollisionConfiguration>("DefaultCollisionConfiguration",
        sol::no_constructor,
        sol::base_classes, sol::bases<btCollisionConfiguration>()
    );

    bt.new_usertype<btDispatcher>("Dispatcher");

    bt.new_usertype<btCollisionDispatcher>("CollisionDispatcher",
        sol::no_constructor,
        sol::base_classes, sol::bases<btDispatcher>()
    );

    bt.new_usertype<btBroadphaseInterface>("BroadphaseInterface");

    bt.new_usertype<btDbvtBroadphase>("DbvtBroadphase",
        sol::no_constructor,
        sol::base_classes, sol::bases<btBroadphaseInterface>()
    );

    bt.new_usertype<btConstraintSolver>("ConstraintSolver");

    bt.new_usertype<btSequentialImpulseConstraintSolver>("SequentialImpulseConstraintSolver",
        sol::no_constructor,
        sol::base_classes, sol::bases<btConstraintSolver>()
    );

    bt.new_usertype<btSoftRigidDynamicsWorld>("SoftRigidDynamicsWorld",
        sol::no_constructor,
        "addRigidBody", [](btSoftRigidDynamicsWorld& world, btRigidBody* body) {
            world.addRigidBody(body, short(1), short(1));
        },
        "removeRigidBody", [](btSoftRigidDynamicsWorld& world, btRigidBody* body) {
            world.removeRigidBody(body);
        },
        "stepSimulation", sol::overload(
            [](btSoftRigidDynamicsWorld& world, btScalar timeStep) {
                return world.stepSimulation(timeStep);
            },
            [](btSoftRigidDynamicsWorld& world, btScalar timeStep, int maxSubSteps, btScalar fixedTimeStep) {
                return world.stepSimulation(timeStep, maxSubSteps, fixedTimeStep);
            }),
        "getCollisionObjectArray", [](btSoftRigidDynamicsWorld& world) {
            std::vector<btCollisionObject*> result;
            auto& objects = world.getCollisionObjectArray();
            result.reserve(objects.size());
            for (int i = 0; i < objects.size(); ++i) {
                result.push_back(objects[i]);
            }
            return sol::as_table(result);
        },
        "setGravity", &btSoftRigidDynamicsWorld::setGravity,
        "addAction", &btSoftRigidDynamicsWorld::addAction,
        "removeAction", &btSoftRigidDynamicsWorld::removeAction,
        sol::base_classes, sol::bases<btDiscreteDynamicsWorld>()
    );

    bt.new_usertype<btDiscreteDynamicsWorld>("DiscreteDynamicsWorld",
        sol::no_constructor,
        "addRigidBody", [](btDiscreteDynamicsWorld& world, btRigidBody* body) {
            world.addRigidBody(body, short(1), short(1));
        },
        "removeRigidBody", [](btDiscreteDynamicsWorld& world, btRigidBody* body) {
            world.removeRigidBody(body);
        },
        "stepSimulation", sol::overload(
            [](btDiscreteDynamicsWorld& world, btScalar timeStep) {
                return world.stepSimulation(timeStep);
            },
            [](btDiscreteDynamicsWorld& world, btScalar timeStep, int maxSubSteps, btScalar fixedTimeStep) {
                return world.stepSimulation(timeStep, maxSubSteps, fixedTimeStep);
            }),
        "getCollisionObjectArray", [](btDiscreteDynamicsWorld& world) {
            std::vector<btCollisionObject*> result;
            auto& objects = world.getCollisionObjectArray();
            result.reserve(objects.size());
            for (int i = 0; i < objects.size(); ++i) {
                result.push_back(objects[i]);
            }
            return sol::as_table(result);
        },
        "setGravity", &btDiscreteDynamicsWorld::setGravity,
        "addAction", &btDiscreteDynamicsWorld::addAction,
        "removeAction", &btDiscreteDynamicsWorld::removeAction,
        sol::base_classes, sol::bases<btDynamicsWorld>()
    );

    bt.new_usertype<btVehicleRaycaster>("VehicleRaycaster");

    bt.new_usertype<btDefaultVehicleRaycaster>("DefaultVehicleRaycaster",
        sol::no_constructor,
        sol::base_classes, sol::bases<btVehicleRaycaster>()
    );

    using VehicleTuning = btRaycastVehicle::btVehicleTuning;
    bt.new_usertype<VehicleTuning>("VehicleTuning",
        sol::no_constructor,
        "m-suspensionStiffness", &VehicleTuning::m_suspensionStiffness,
        "m-suspensionCompression", &VehicleTuning::m_suspensionCompression,
        "m-suspensionDamping", &VehicleTuning::m_suspensionDamping,
        "m-maxSuspensionTravelCm", &VehicleTuning::m_maxSuspensionTravelCm,
        "m-frictionSlip", &VehicleTuning::m_frictionSlip,
        "m-maxSuspensionForce", &VehicleTuning::m_maxSuspensionForce
    );

    bt.new_usertype<btRaycastVehicle>("RaycastVehicle",
        sol::no_constructor,
        "applyEngineForce", &btRaycastVehicle::applyEngineForce,
        "setBrake", &btRaycastVehicle::setBrake,
        "setSteeringValue", &btRaycastVehicle::setSteeringValue,
        "setCoordinateSystem", &btRaycastVehicle::setCoordinateSystem,
        "resetSuspension", &btRaycastVehicle::resetSuspension,
        "getNumWheels", &btRaycastVehicle::getNumWheels,
        "getChassisWorldTransform", [](btRaycastVehicle& self) {
            return btTransform(self.getChassisWorldTransform());
        },
        "addWheel", [](btRaycastVehicle& self,
                       const btVector3& connectionPointCS0,
                       const btVector3& wheelDirectionCS0,
                       const btVector3& wheelAxleCS,
                       btScalar suspensionRestLength,
                       btScalar wheelRadius,
                       const VehicleTuning& tuning,
                       bool isFrontWheel) {
            self.addWheel(connectionPointCS0, wheelDirectionCS0, wheelAxleCS,
                          suspensionRestLength, wheelRadius, tuning, isFrontWheel);
        },
        "updateWheelTransform", sol::overload(
            [](btRaycastVehicle& self, int wheel, bool interpolated) {
                self.updateWheelTransform(wheel, interpolated);
            },
            [](btRaycastVehicle& self, int wheel) {
                self.updateWheelTransform(wheel);
            })
    );

    bt.set_function("Vector3", sol::overload(
        []() { return btVector3(0, 0, 0); },
        [](float x, float y, float z) { return btVector3(x, y, z); }
    ));
    bt.set_function("Quaternion", sol::overload(
        []() { return btQuaternion(0, 0, 0, 1); },
        [](float x, float y, float z, float w) { return btQuaternion(x, y, z, w); }
    ));
    bt.set_function("Transform", sol::overload(
        []() { return btTransform(); },
        [](const btQuaternion& rotation, const btVector3& origin) { return btTransform(rotation, origin); }
    ));
    bt.set_function("TriangleMesh", []() { return std::make_unique<btTriangleMesh>(); });
    bt.set_function("BvhTriangleMeshShape", sol::overload(
        [](btTriangleMesh* mesh) { return std::make_unique<btBvhTriangleMeshShape>(mesh, true); },
        [](btTriangleMesh* mesh, bool useQuantizedAabbCompression) {
            return std::make_unique<btBvhTriangleMeshShape>(mesh, useQuantizedAabbCompression);
        }
    ));
    bt.set_function("StaticPlaneShape", [](const btVector3& normal, btScalar constant) {
        return std::make_unique<btStaticPlaneShape>(normal, constant);
    });
    bt.set_function("BoxShape", [](const btVector3& halfExtents) {
        return std::make_unique<btBoxShape>(halfExtents);
    });
    bt.set_function("DefaultMotionState", sol::overload(
        []() { return std::make_unique<btDefaultMotionState>(); },
        [](const btTransform& transform) { return std::make_unique<btDefaultMotionState>(transform); }
    ));
    bt.set_function("RigidBodyConstructionInfo",
        [](btScalar mass, btMotionState* motionState, btCollisionShape* shape,
           sol::optional<btVector3> localInertia) {
            btVector3 inertia(0, 0, 0);
            if (localInertia) {
                inertia = *localInertia;
            }
            return RigidBodyCI(mass, motionState, shape, inertia);
        });
    bt.set_function("RigidBody", [](const RigidBodyCI& info) {
        return std::make_unique<btRigidBody>(info);
    });
    bt.set_function("DefaultCollisionConfiguration", []() {
        return std::make_unique<btDefaultCollisionConfiguration>();
    });
    bt.set_function("CollisionDispatcher", [](btCollisionConfiguration* config) {
        return std::make_unique<btCollisionDispatcher>(config);
    });
    bt.set_function("DbvtBroadphase", []() {
        return std::make_unique<btDbvtBroadphase>();
    });
    bt.set_function("SequentialImpulseConstraintSolver", []() {
        return std::make_unique<btSequentialImpulseConstraintSolver>();
    });
    bt.set_function("SoftRigidDynamicsWorld",
        [](btDispatcher* dispatcher, btBroadphaseInterface* broadphase,
           btConstraintSolver* solver, btCollisionConfiguration* config) {
            return std::make_unique<btSoftRigidDynamicsWorld>(dispatcher, broadphase, solver, config);
        });
    bt.set_function("DiscreteDynamicsWorld",
        [](btDispatcher* dispatcher, btBroadphaseInterface* broadphase,
           btConstraintSolver* solver, btCollisionConfiguration* config) {
            return std::make_unique<btDiscreteDynamicsWorld>(dispatcher, broadphase, solver, config);
        });
    bt.set_function("DefaultVehicleRaycaster", [](btDynamicsWorld* world) {
        return std::make_unique<btDefaultVehicleRaycaster>(world);
    });
    bt.set_function("VehicleTuning", []() { return std::make_unique<VehicleTuning>(); });
    bt.set_function("RaycastVehicle",
        [](const VehicleTuning& tuning, btRigidBody* body, btVehicleRaycaster* raycaster) {
            return std::make_unique<btRaycastVehicle>(tuning, body, raycaster);
        });

    bt.new_usertype<Physics>("Physics",
        "setGravity", &Physics::setGravity,
        "addRigidBody", &Physics::addRigidBody,
        "removeRigidBody", &Physics::removeRigidBody,
        "addAction", &Physics::addAction,
        "removeAction", &Physics::removeAction,
        "getWorld", &Physics::getWorld,
        "update", &Physics::update
    );
    return bt;
}

} // namespace

void lua_bind_physics(sol::state& lua) {
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("bt", [](sol::this_state state) {
        sol::state_view lua(state);
        return create_physics_table(lua);
    });
}
