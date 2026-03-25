#include <sol/sol.hpp>
#include <algorithm>
#include <memory>
#include <limits>
#include <vector>
#include <stdexcept>
#include <BulletCollision/CollisionShapes/btBvhTriangleMeshShape.h>
#include <BulletCollision/CollisionShapes/btBoxShape.h>
#include <BulletCollision/CollisionShapes/btHeightfieldTerrainShape.h>
#include <BulletCollision/CollisionShapes/btSphereShape.h>
#include <BulletCollision/CollisionShapes/btStaticPlaneShape.h>
#include <BulletCollision/CollisionShapes/btTriangleMesh.h>
#include <btBulletDynamicsCommon.h>
#include <BulletSoftBody/btSoftRigidDynamicsWorld.h>
#include <BulletSoftBody/btSoftBodyHelpers.h>
#include <BulletDynamics/Vehicle/btRaycastVehicle.h>
#include <BulletDynamics/Vehicle/btVehicleRaycaster.h>

#include "physics.h"

namespace {

class LuaHeightfieldTerrainShape : public btHeightfieldTerrainShape {
public:
    LuaHeightfieldTerrainShape(int width,
                               int length,
                               std::unique_ptr<btScalar[]> heights,
                               btScalar min_height,
                               btScalar max_height,
                               int up_axis,
                               bool flip_quad_edges)
        : btHeightfieldTerrainShape(width,
                                    length,
                                    heights.get(),
                                    btScalar(1.0),
                                    min_height,
                                    max_height,
                                    up_axis,
                                    PHY_FLOAT,
                                    flip_quad_edges)
        , heights_(std::move(heights))
    {
    }

private:
    std::unique_ptr<btScalar[]> heights_;
};

std::unique_ptr<btScalar[]> copy_heightfield_samples(const sol::table& heights, int sample_count)
{
    auto out = std::make_unique<btScalar[]>(sample_count);
    for (int i = 0; i < sample_count; ++i) {
        sol::object value = heights[i + 1];
        if (!value.valid() || !value.is<double>()) {
            throw sol::error("bt.HeightfieldTerrainShape heights must be a dense numeric array");
        }
        out[i] = static_cast<btScalar>(value.as<double>());
    }
    return out;
}

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
        "getShapeType", &btCollisionShape::getShapeType,
        "setLocalScaling", [](btCollisionShape& self, const btVector3& scaling) {
            self.setLocalScaling(scaling);
        },
        "getLocalScaling", [](btCollisionShape& self) {
            return self.getLocalScaling();
        },
        "calculateLocalInertia", [](btCollisionShape& self, btScalar mass, btVector3& inertia) {
            self.calculateLocalInertia(mass, inertia);
        }
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

    bt.new_usertype<LuaHeightfieldTerrainShape>("HeightfieldTerrainShape",
        sol::no_constructor,
        "setLocalScaling", &LuaHeightfieldTerrainShape::setLocalScaling,
        "getLocalScaling", [](LuaHeightfieldTerrainShape& self) {
            return self.getLocalScaling();
        },
        "setUseDiamondSubdivision", &LuaHeightfieldTerrainShape::setUseDiamondSubdivision,
        "setUseZigzagSubdivision", &LuaHeightfieldTerrainShape::setUseZigzagSubdivision,
        "setFlipTriangleWinding", &LuaHeightfieldTerrainShape::setFlipTriangleWinding,
        "buildAccelerator", &LuaHeightfieldTerrainShape::buildAccelerator,
        sol::base_classes, sol::bases<btCollisionShape>()
    );

    bt.new_usertype<btStaticPlaneShape>("StaticPlaneShape",
        sol::no_constructor,
        sol::base_classes, sol::bases<btCollisionShape>()
    );

    bt.new_usertype<btBoxShape>("BoxShape",
        sol::no_constructor,
        sol::base_classes, sol::bases<btCollisionShape>()
    );

    bt.new_usertype<btSphereShape>("SphereShape",
        sol::no_constructor,
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
        "m-startWorldTransform", &RigidBodyCI::m_startWorldTransform,
        "m-collisionShape", &RigidBodyCI::m_collisionShape,
        "m-localInertia", &RigidBodyCI::m_localInertia,
        "m-linearDamping", &RigidBodyCI::m_linearDamping,
        "m-angularDamping", &RigidBodyCI::m_angularDamping,
        "m-friction", &RigidBodyCI::m_friction,
        "m-rollingFriction", &RigidBodyCI::m_rollingFriction,
        "m-spinningFriction", &RigidBodyCI::m_spinningFriction,
        "m-restitution", &RigidBodyCI::m_restitution,
        "m-linearSleepingThreshold", &RigidBodyCI::m_linearSleepingThreshold,
        "m-angularSleepingThreshold", &RigidBodyCI::m_angularSleepingThreshold,
        "m-additionalDamping", &RigidBodyCI::m_additionalDamping,
        "m-additionalDampingFactor", &RigidBodyCI::m_additionalDampingFactor,
        "m-additionalLinearDampingThresholdSqr", &RigidBodyCI::m_additionalLinearDampingThresholdSqr,
        "m-additionalAngularDampingThresholdSqr", &RigidBodyCI::m_additionalAngularDampingThresholdSqr,
        "m-additionalAngularDampingFactor", &RigidBodyCI::m_additionalAngularDampingFactor
    );

    bt.new_usertype<btCollisionObject>("CollisionObject",
        sol::no_constructor,
        "getCollisionShape", [](btCollisionObject& self) {
            return self.getCollisionShape();
        },
        "setCollisionShape", &btCollisionObject::setCollisionShape,
        "getActivationState", &btCollisionObject::getActivationState,
        "setActivationState", &btCollisionObject::setActivationState,
        "forceActivationState", &btCollisionObject::forceActivationState,
        "activate", sol::overload(
            [](btCollisionObject& self) {
                self.activate();
            },
            [](btCollisionObject& self, bool forceActivation) {
                self.activate(forceActivation);
            }
        ),
        "isActive", &btCollisionObject::isActive,
        "isStaticObject", &btCollisionObject::isStaticObject,
        "isKinematicObject", &btCollisionObject::isKinematicObject,
        "isStaticOrKinematicObject", &btCollisionObject::isStaticOrKinematicObject,
        "hasContactResponse", &btCollisionObject::hasContactResponse,
        "getAnisotropicFriction", [](btCollisionObject& self) {
            return self.getAnisotropicFriction();
        },
        "setAnisotropicFriction", sol::overload(
            [](btCollisionObject& self, const btVector3& anisotropicFriction) {
                self.setAnisotropicFriction(anisotropicFriction);
            },
            [](btCollisionObject& self, const btVector3& anisotropicFriction, int frictionMode) {
                self.setAnisotropicFriction(anisotropicFriction, frictionMode);
            }
        ),
        "hasAnisotropicFriction", sol::overload(
            [](btCollisionObject& self) {
                return self.hasAnisotropicFriction();
            },
            [](btCollisionObject& self, int frictionMode) {
                return self.hasAnisotropicFriction(frictionMode);
            }
        ),
        "setContactProcessingThreshold", &btCollisionObject::setContactProcessingThreshold,
        "getContactProcessingThreshold", &btCollisionObject::getContactProcessingThreshold,
        "setDeactivationTime", &btCollisionObject::setDeactivationTime,
        "getDeactivationTime", &btCollisionObject::getDeactivationTime,
        "setRestitution", &btCollisionObject::setRestitution,
        "getRestitution", &btCollisionObject::getRestitution,
        "setFriction", &btCollisionObject::setFriction,
        "getFriction", &btCollisionObject::getFriction,
        "setRollingFriction", &btCollisionObject::setRollingFriction,
        "getRollingFriction", &btCollisionObject::getRollingFriction,
        "setSpinningFriction", &btCollisionObject::setSpinningFriction,
        "getSpinningFriction", &btCollisionObject::getSpinningFriction,
        "setContactStiffnessAndDamping", &btCollisionObject::setContactStiffnessAndDamping,
        "getContactStiffness", &btCollisionObject::getContactStiffness,
        "getContactDamping", &btCollisionObject::getContactDamping,
        "getWorldTransform", [](btCollisionObject& self) {
            return btTransform(self.getWorldTransform());
        },
        "setWorldTransform", &btCollisionObject::setWorldTransform,
        "getInterpolationWorldTransform", [](btCollisionObject& self) {
            return btTransform(self.getInterpolationWorldTransform());
        },
        "setInterpolationWorldTransform", &btCollisionObject::setInterpolationWorldTransform,
        "setInterpolationLinearVelocity", &btCollisionObject::setInterpolationLinearVelocity,
        "setInterpolationAngularVelocity", &btCollisionObject::setInterpolationAngularVelocity,
        "getInterpolationLinearVelocity", [](btCollisionObject& self) {
            return self.getInterpolationLinearVelocity();
        },
        "getInterpolationAngularVelocity", [](btCollisionObject& self) {
            return self.getInterpolationAngularVelocity();
        },
        "getHitFraction", &btCollisionObject::getHitFraction,
        "setHitFraction", &btCollisionObject::setHitFraction,
        "getCollisionFlags", &btCollisionObject::getCollisionFlags,
        "setCollisionFlags", &btCollisionObject::setCollisionFlags,
        "getCcdSweptSphereRadius", &btCollisionObject::getCcdSweptSphereRadius,
        "setCcdSweptSphereRadius", &btCollisionObject::setCcdSweptSphereRadius,
        "getCcdMotionThreshold", &btCollisionObject::getCcdMotionThreshold,
        "setCcdMotionThreshold", &btCollisionObject::setCcdMotionThreshold,
        "getUserIndex", &btCollisionObject::getUserIndex,
        "setUserIndex", &btCollisionObject::setUserIndex,
        "getUserIndex2", &btCollisionObject::getUserIndex2,
        "setUserIndex2", &btCollisionObject::setUserIndex2,
        "getUserIndex3", &btCollisionObject::getUserIndex3,
        "setUserIndex3", &btCollisionObject::setUserIndex3
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
        "setCenterOfMassTransform", &btRigidBody::setCenterOfMassTransform,
        "getCenterOfMassPosition", [](btRigidBody& self) {
            return self.getCenterOfMassPosition();
        },
        "getOrientation", [](btRigidBody& self) {
            return self.getOrientation();
        },
        "setMassProps", &btRigidBody::setMassProps,
        "getMass", &btRigidBody::getMass,
        "getInvMass", &btRigidBody::getInvMass,
        "setLinearVelocity", &btRigidBody::setLinearVelocity,
        "setAngularVelocity", &btRigidBody::setAngularVelocity,
        "getLinearVelocity", [](btRigidBody& self) {
            return self.getLinearVelocity();
        },
        "getAngularVelocity", [](btRigidBody& self) {
            return self.getAngularVelocity();
        },
        "getVelocityInLocalPoint", &btRigidBody::getVelocityInLocalPoint,
        "setGravity", &btRigidBody::setGravity,
        "clearGravity", &btRigidBody::clearGravity,
        "getGravity", [](btRigidBody& self) {
            return self.getGravity();
        },
        "setDamping", &btRigidBody::setDamping,
        "getLinearDamping", &btRigidBody::getLinearDamping,
        "getAngularDamping", &btRigidBody::getAngularDamping,
        "applyDamping", &btRigidBody::applyDamping,
        "getLinearSleepingThreshold", &btRigidBody::getLinearSleepingThreshold,
        "getAngularSleepingThreshold", &btRigidBody::getAngularSleepingThreshold,
        "setSleepingThresholds", &btRigidBody::setSleepingThresholds,
        "getLinearFactor", [](btRigidBody& self) {
            return self.getLinearFactor();
        },
        "setLinearFactor", &btRigidBody::setLinearFactor,
        "getAngularFactor", [](btRigidBody& self) {
            return self.getAngularFactor();
        },
        "setAngularFactor", sol::overload(
            [](btRigidBody& self, const btVector3& angularFactor) {
                self.setAngularFactor(angularFactor);
            },
            [](btRigidBody& self, btScalar angularFactor) {
                self.setAngularFactor(angularFactor);
            }
        ),
        "getTotalForce", [](btRigidBody& self) {
            return self.getTotalForce();
        },
        "getTotalTorque", [](btRigidBody& self) {
            return self.getTotalTorque();
        },
        "getInvInertiaDiagLocal", [](btRigidBody& self) {
            return self.getInvInertiaDiagLocal();
        },
        "setInvInertiaDiagLocal", &btRigidBody::setInvInertiaDiagLocal,
        "applyForce", &btRigidBody::applyCentralForce,
        "applyCentralForce", &btRigidBody::applyCentralForce,
        "applyTorque", &btRigidBody::applyTorque,
        "applyForceAtPosition", &btRigidBody::applyForce,
        "applyCentralImpulse", &btRigidBody::applyCentralImpulse,
        "applyTorqueImpulse", &btRigidBody::applyTorqueImpulse,
        "applyImpulse", &btRigidBody::applyImpulse,
        "clearForces", &btRigidBody::clearForces,
        "translate", &btRigidBody::translate,
        "isInWorld", &btRigidBody::isInWorld,
        "getFlags", &btRigidBody::getFlags,
        "setFlags", &btRigidBody::setFlags,
        "setPosition", &btRigidBody::setWorldTransform,
        "getPosition", [](btRigidBody& self) {
            return btTransform(self.getWorldTransform());
        },
        sol::base_classes, sol::bases<btCollisionObject>()
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
        "getGravity", &btSoftRigidDynamicsWorld::getGravity,
        "clearForces", &btSoftRigidDynamicsWorld::clearForces,
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
        "getGravity", &btDiscreteDynamicsWorld::getGravity,
        "clearForces", &btDiscreteDynamicsWorld::clearForces,
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
    bt.set_function("HeightfieldTerrainShape",
        [](int width,
           int length,
           sol::table heights,
           btScalar minHeight,
           btScalar maxHeight,
           sol::optional<int> upAxis,
           sol::optional<bool> flipQuadEdges) {
            if (width <= 1 || length <= 1) {
                throw sol::error("bt.HeightfieldTerrainShape requires width and length greater than 1");
            }
            const int sample_count = width * length;
            const int table_length = static_cast<int>(heights.size());
            if (table_length != sample_count) {
                throw sol::error("bt.HeightfieldTerrainShape heights length must equal width * length");
            }
            auto copied_heights = copy_heightfield_samples(heights, sample_count);
            return std::make_unique<LuaHeightfieldTerrainShape>(width,
                                                                length,
                                                                std::move(copied_heights),
                                                                minHeight,
                                                                maxHeight,
                                                                upAxis.value_or(1),
                                                                flipQuadEdges.value_or(false));
        });
    bt.set_function("StaticPlaneShape", [](const btVector3& normal, btScalar constant) {
        return std::make_unique<btStaticPlaneShape>(normal, constant);
    });
    bt.set_function("BoxShape", [](const btVector3& halfExtents) {
        return std::make_unique<btBoxShape>(halfExtents);
    });
    bt.set_function("SphereShape", [](btScalar radius) {
        return std::make_unique<btSphereShape>(radius);
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
        "updateSingleAabb", &Physics::updateSingleAabb,
        "syncMovedRigidBody", &Physics::syncMovedRigidBody,
        "addAction", &Physics::addAction,
        "removeAction", &Physics::removeAction,
        "getWorld", &Physics::getWorld,
        "update", &Physics::update
    );

    bt["ACTIVE_TAG"] = ACTIVE_TAG;
    bt["ISLAND_SLEEPING"] = ISLAND_SLEEPING;
    bt["WANTS_DEACTIVATION"] = WANTS_DEACTIVATION;
    bt["DISABLE_DEACTIVATION"] = DISABLE_DEACTIVATION;
    bt["DISABLE_SIMULATION"] = DISABLE_SIMULATION;

    bt["CF_STATIC_OBJECT"] = btCollisionObject::CF_STATIC_OBJECT;
    bt["CF_KINEMATIC_OBJECT"] = btCollisionObject::CF_KINEMATIC_OBJECT;
    bt["CF_NO_CONTACT_RESPONSE"] = btCollisionObject::CF_NO_CONTACT_RESPONSE;
    bt["CF_CUSTOM_MATERIAL_CALLBACK"] = btCollisionObject::CF_CUSTOM_MATERIAL_CALLBACK;
    bt["CF_CHARACTER_OBJECT"] = btCollisionObject::CF_CHARACTER_OBJECT;
    bt["CF_DISABLE_VISUALIZE_OBJECT"] = btCollisionObject::CF_DISABLE_VISUALIZE_OBJECT;
    bt["CF_DISABLE_SPU_COLLISION_PROCESSING"] = btCollisionObject::CF_DISABLE_SPU_COLLISION_PROCESSING;
    bt["CF_HAS_CONTACT_STIFFNESS_DAMPING"] = btCollisionObject::CF_HAS_CONTACT_STIFFNESS_DAMPING;
    bt["CF_HAS_CUSTOM_DEBUG_RENDERING_COLOR"] = btCollisionObject::CF_HAS_CUSTOM_DEBUG_RENDERING_COLOR;
    bt["CF_HAS_FRICTION_ANCHOR"] = btCollisionObject::CF_HAS_FRICTION_ANCHOR;
    bt["CF_HAS_COLLISION_SOUND_TRIGGER"] = btCollisionObject::CF_HAS_COLLISION_SOUND_TRIGGER;

    bt["CF_ANISOTROPIC_FRICTION_DISABLED"] = btCollisionObject::CF_ANISOTROPIC_FRICTION_DISABLED;
    bt["CF_ANISOTROPIC_FRICTION"] = btCollisionObject::CF_ANISOTROPIC_FRICTION;
    bt["CF_ANISOTROPIC_ROLLING_FRICTION"] = btCollisionObject::CF_ANISOTROPIC_ROLLING_FRICTION;

    bt["BT_DISABLE_WORLD_GRAVITY"] = BT_DISABLE_WORLD_GRAVITY;
    bt["BT_ENABLE_GYROSCOPIC_FORCE_EXPLICIT"] = BT_ENABLE_GYROSCOPIC_FORCE_EXPLICIT;
    bt["BT_ENABLE_GYROSCOPIC_FORCE_IMPLICIT_WORLD"] = BT_ENABLE_GYROSCOPIC_FORCE_IMPLICIT_WORLD;
    bt["BT_ENABLE_GYROSCOPIC_FORCE_IMPLICIT_BODY"] = BT_ENABLE_GYROSCOPIC_FORCE_IMPLICIT_BODY;
    bt["BT_ENABLE_GYROPSCOPIC_FORCE"] = BT_ENABLE_GYROPSCOPIC_FORCE;
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
