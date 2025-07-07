#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>

#include "physics.h"

namespace py = pybind11;

void bind_btScalar(py::module_ &m) {
    m.def("Scalar", [](float value) { return value; }, "Expose btScalar as float");
}

// Vector3 class
void bind_btVector3(py::module_ &m) {
    py::class_<btVector3>(m, "Vector3")
        .def(py::init<>())
        .def(py::init<float, float, float>())
        .def("x", &btVector3::getX)
        .def("y", &btVector3::getY)
        .def("z", &btVector3::getZ)
        .def("setX", &btVector3::setX)
        .def("setY", &btVector3::setY)
        .def("setZ", &btVector3::setZ)
        .def("length", &btVector3::length)
        .def("normalize", &btVector3::normalize)
        .def("to_numpy", [](const btVector3 &v) {
            py::array_t<float> arr(3);  // Create array with 3 elements
            auto buf = arr.mutable_unchecked<1>();  // Get a mutable 1D buffer
            buf(0) = v.x();
            buf(1) = v.y();
            buf(2) = v.z();
            return arr;
        })
        .def("__repr__", [](const btVector3 &v) {
            return "<Vector3(" + std::to_string(v.x()) + ", " + std::to_string(v.y()) + ", " + std::to_string(v.z()) + ")>";
        });
}

// Quaternion class
void bind_btQuaternion(py::module_ &m) {
    py::class_<btQuaternion>(m, "Quaternion")
        .def(py::init<>())
        .def(py::init<float, float, float, float>())
        .def("x", &btQuaternion::getX)
        .def("y", &btQuaternion::getY)
        .def("z", &btQuaternion::getZ)
        .def("w", &btQuaternion::getW)
        .def("normalize", &btQuaternion::normalize)
        .def("to_numpy", [](const btQuaternion &v) {
            py::array_t<float> arr(4);  // Create array with 3 elements
            auto buf = arr.mutable_unchecked<1>();  // Get a mutable 1D buffer
            buf(0) = v.w();
            buf(1) = v.x();
            buf(2) = v.y();
            buf(3) = v.z();
            return arr;
        })
        .def("__repr__", [](const btQuaternion &q) {
            return "<Quaternion(" + std::to_string(q.x()) + ", " + std::to_string(q.y()) + ", " + std::to_string(q.z()) + ", " + std::to_string(q.w()) + ")>";
        });
}

// Collision Shape base class
void bind_btCollisionShape(py::module_ &m) {
    py::class_<btCollisionShape>(m, "CollisionShape")
        .def("getName", &btCollisionShape::getName)
        .def("getShapeType", &btCollisionShape::getShapeType);
}

void bind_btTriangleMesh(py::module_ &m) {
    py::class_<btTriangleMesh>(m, "TriangleMesh")
        .def(py::init<>())
        .def("addTriangle",
             py::overload_cast<const btVector3 &, const btVector3 &, const btVector3 &, bool>(&btTriangleMesh::addTriangle),
             py::arg("v0"), py::arg("v1"), py::arg("v2"), py::arg("removeDuplicateVertices") = false);
}

void bind_btBvhTriangleMeshShape(py::module_ &m) {
    py::class_<btBvhTriangleMeshShape, btCollisionShape>(m, "BvhTriangleMeshShape")
        .def(py::init<btTriangleMesh *, bool>(),
             py::arg("meshInterface"), py::arg("useQuantizedAabbCompression") = true);
}

void bind_btStaticPlaneShape(py::module_ &m) {
    py::class_<btStaticPlaneShape, btCollisionShape>(m, "StaticPlaneShape")
        .def(py::init<const btVector3&, int>());
}

// Box shape class
void bind_btBoxShape(py::module_ &m) {
    py::class_<btBoxShape, btCollisionShape>(m, "BoxShape")
        .def(py::init<const btVector3&>())  // Constructor taking a btVector3
        .def("setLocalScaling", &btBoxShape::setLocalScaling, "Set local scaling of the box shape")
        .def("getLocalScaling", &btBoxShape::getLocalScaling, "Get the current local scaling of the box shape")
        .def("calculateLocalInertia", &btBoxShape::calculateLocalInertia);
}

void bind_btMotionState(py::module_ &m) {
    py::class_<btMotionState>(m, "MotionState")
        .def("getWorldTransform", &btMotionState::getWorldTransform);
}

void bind_btDefaultMotionState(py::module_ &m) {
    py::class_<btDefaultMotionState, btMotionState>(m, "DefaultMotionState")
        .def(py::init<const btTransform&>(), py::arg("initialTransform"))
        .def("getWorldTransform", &btDefaultMotionState::getWorldTransform)
        .def("setWorldTransform", &btDefaultMotionState::setWorldTransform);
}

void bind_btTransform(py::module_ &m) {
    py::class_<btTransform>(m, "Transform")
        .def(py::init<>())  // Default constructor
        .def(py::init<const btQuaternion&, const btVector3&>(), py::arg("rotation"), py::arg("position"))
        .def("setOrigin", py::overload_cast<const btVector3&>(&btTransform::setOrigin), "Set the origin of the transform")
        .def("getOrigin", py::overload_cast<>(&btTransform::getOrigin), "Get the origin of the transform")
        .def("setRotation", &btTransform::setRotation)
        .def("getRotation", &btTransform::getRotation)
        .def("setIdentity", &btTransform::setIdentity)
        .def("inverse", &btTransform::inverse);
}

void bind_btRigidBody(py::module_ &m) {
    py::class_<btRigidBody::btRigidBodyConstructionInfo>(m, "RigidBodyConstructionInfo")
        .def(py::init<btScalar, btMotionState*, btCollisionShape*, const btVector3&>(),
             py::arg("mass"), py::arg("motionState"), py::arg("shape"), py::arg("localInertia") = btVector3(0, 0, 0))
        .def_readwrite("m_mass", &btRigidBody::btRigidBodyConstructionInfo::m_mass)
        .def_readwrite("m_motionState", &btRigidBody::btRigidBodyConstructionInfo::m_motionState)
        .def_readwrite("m_collisionShape", &btRigidBody::btRigidBodyConstructionInfo::m_collisionShape)
        .def_readwrite("m_localInertia", &btRigidBody::btRigidBodyConstructionInfo::m_localInertia);

    py::class_<btRigidBody>(m, "RigidBody")
        .def(py::init<const btRigidBody::btRigidBodyConstructionInfo&>())
        .def("setMassProps", &btRigidBody::setMassProps)
        .def("setLinearVelocity", &btRigidBody::setLinearVelocity)
        .def("getLinearVelocity", &btRigidBody::getLinearVelocity)
        .def("applyForce", &btRigidBody::applyCentralForce)
        .def("getMotionState", py::overload_cast<>(&btRigidBody::getMotionState), py::return_value_policy::reference,
             "Get motion state (non-const)")
        .def("setPosition", (void(btRigidBody::*)(const btTransform &)) &btRigidBody::setWorldTransform)
        .def("getPosition", (const btTransform&(btRigidBody::*)() const) &btRigidBody::getWorldTransform);
}

void bind_btCollisionConfiguration(py::module_ &m) {
    py::class_<btCollisionConfiguration>(m, "CollisionConfiguration");
}

void bind_btDefaultCollisionConfiguration(py::module_ &m) {
    py::class_<btDefaultCollisionConfiguration, btCollisionConfiguration>(m, "DefaultCollisionConfiguration")
        .def(py::init<>());
}

void bind_btDispatcher(py::module_ &m) {
    py::class_<btDispatcher>(m, "Dispatcher");
}

void bind_btCollisionDispatcher(py::module_ &m) {
    py::class_<btCollisionDispatcher, btDispatcher>(m, "CollisionDispatcher")
        .def(py::init<btCollisionConfiguration*>());
}

void bind_btBroadphaseInterface(py::module_ &m) {
    py::class_<btBroadphaseInterface>(m, "BroadphaseInterface");
}

void bind_btDbvtBroadphase(py::module_ &m) {
    py::class_<btDbvtBroadphase, btBroadphaseInterface>(m, "DbvtBroadphase")
        .def(py::init<>());
}

void bind_btConstraintSolver(py::module_ &m) {
    py::class_<btConstraintSolver>(m, "ConstraintSolver");
}

void bind_btSequentialImpulseConstraintSolver(py::module_ &m) {
    py::class_<btSequentialImpulseConstraintSolver, btConstraintSolver>(m, "SequentialImpulseConstraintSolver")
        .def(py::init<>());
}

void bind_btSoftRigidDynamicsWorld(py::module_ &m) {
    py::class_<btSoftRigidDynamicsWorld>(m, "SoftRigidDynamicsWorld")
        .def(py::init<btDispatcher*, btBroadphaseInterface*, btConstraintSolver*, btCollisionConfiguration*>())
        .def("addRigidBody", 
                [](btSoftRigidDynamicsWorld& world, btRigidBody* body) {
                world.addRigidBody(body, short(1), short(1));  // Default group and mask values
                },
                "Add a rigid body to the dynamics world")
        .def("removeRigidBody", 
                [](btSoftRigidDynamicsWorld& world, btRigidBody* body) {
                world.removeRigidBody(body);
                })
        .def("stepSimulation", &btSoftRigidDynamicsWorld::stepSimulation)
        .def("getCollisionObjectArray", (btCollisionObjectArray&(btSoftRigidDynamicsWorld::*)()) &btSoftRigidDynamicsWorld::getCollisionObjectArray)
        .def("setGravity", &btSoftRigidDynamicsWorld::setGravity, "Set gravity for the dynamics world");
}
void bind_btDiscreteDynamicsWorld(py::module_ &m) {
    py::class_<btDiscreteDynamicsWorld>(m, "DiscreteDynamicsWorld")
        .def(py::init<btDispatcher*, btBroadphaseInterface*, btConstraintSolver*, btCollisionConfiguration*>())
        .def("addRigidBody", 
                [](btDiscreteDynamicsWorld& world, btRigidBody* body) {
                world.addRigidBody(body, short(1), short(1));  // Default group and mask values
                },
                "Add a rigid body to the dynamics world")
        .def("removeRigidBody", 
                [](btDiscreteDynamicsWorld& world, btRigidBody* body) {
                world.removeRigidBody(body);
                })
        .def("stepSimulation", &btDiscreteDynamicsWorld::stepSimulation)
        .def("getCollisionObjectArray", (btCollisionObjectArray&(btDiscreteDynamicsWorld::*)()) &btDiscreteDynamicsWorld::getCollisionObjectArray)
        .def("setGravity", &btDiscreteDynamicsWorld::setGravity, "Set gravity for the dynamics world");
}

// Constants
void bind_bullet_constants(py::module_ &m) {
    //m.attr("CF_STATIC_OBJECT") = btRigidBody::CF_STATIC_OBJECT;
    //m.attr("CF_KINEMATIC_OBJECT") = btRigidBody::CF_KINEMATIC_OBJECT;
    //m.attr("CF_DYNAMIC_OBJECT") = btRigidBody::CF_DYNAMIC_OBJECT;
}

PYBIND11_MODULE(bullet, m) {
    m.doc() = "Bullet Physics Module";

    bind_btScalar(m);
    bind_btVector3(m);
    bind_btQuaternion(m);
    bind_btCollisionShape(m);
    bind_btTriangleMesh(m);
    bind_btBvhTriangleMeshShape(m);
    bind_btBoxShape(m);
    bind_btStaticPlaneShape(m);
    bind_btMotionState(m);
    bind_btDefaultMotionState(m);
    bind_btTransform(m);
    bind_btRigidBody(m);
    bind_btCollisionConfiguration(m);
    bind_btDefaultCollisionConfiguration(m);
    bind_btDispatcher(m);
    bind_btCollisionDispatcher(m);
    bind_btBroadphaseInterface(m);
    bind_btDbvtBroadphase(m);
    bind_btConstraintSolver(m);
    bind_btSequentialImpulseConstraintSolver(m);
    bind_btSoftRigidDynamicsWorld(m);
    bind_btDiscreteDynamicsWorld(m);
    bind_bullet_constants(m);

    py::class_<Physics>(m, "Physics")
        .def("setGravity", &Physics::setGravity)
        .def("addRigidBody", &Physics::addRigidBody)
        .def("removeRigidBody", &Physics::removeRigidBody);
}
