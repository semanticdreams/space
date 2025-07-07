#include "physics.h"

Physics::Physics() {
    broadphase = new btDbvtBroadphase();
    collisionConfiguration = new btDefaultCollisionConfiguration();
    dispatcher = new btCollisionDispatcher(collisionConfiguration);
    solver = new btSequentialImpulseConstraintSolver();
    dynamicsWorld = new btSoftRigidDynamicsWorld(dispatcher, broadphase, solver, collisionConfiguration);
}

Physics::~Physics()
{
    // Remove and delete all rigid bodies
    for (int i = dynamicsWorld->getNumCollisionObjects() - 1; i >= 0; i--) {
        btCollisionObject* obj = dynamicsWorld->getCollisionObjectArray()[i];

        btRigidBody* body = btRigidBody::upcast(obj);
        if (body && body->getMotionState()) {
            delete body->getMotionState();
        }

        dynamicsWorld->removeCollisionObject(obj);
        delete obj;
    }

    delete dynamicsWorld;
    delete solver;
    delete broadphase;
    delete dispatcher;
    delete collisionConfiguration;
}

void Physics::update(uint32_t dt) {
    // dt, 10, 1 / 60.f
    dynamicsWorld->stepSimulation(1 / 60.f, 10, 1 / 60.f);
}

void Physics::setGravity(float x, float y, float z)
{
    dynamicsWorld->setGravity(btVector3(x, y, z));
}

void Physics::addRigidBody(btRigidBody* body)
{
    dynamicsWorld->addRigidBody(body);
}

void Physics::removeRigidBody(btRigidBody* body)
{
    dynamicsWorld->removeRigidBody(body);
}
