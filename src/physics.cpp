#include "physics.h"

Physics::Physics() {
    broadphase = new btDbvtBroadphase();
    collisionConfiguration = new btDefaultCollisionConfiguration();
    dispatcher = new btCollisionDispatcher(collisionConfiguration);
    solver = new btSequentialImpulseConstraintSolver();
    dynamicsWorld = new btDiscreteDynamicsWorld(dispatcher, broadphase, solver, collisionConfiguration);
}

Physics::~Physics()
{
    // Remove all rigid bodies; Lua owns the objects themselves via sol2.
    for (int i = dynamicsWorld->getNumCollisionObjects() - 1; i >= 0; i--) {
        btCollisionObject* obj = dynamicsWorld->getCollisionObjectArray()[i];
        dynamicsWorld->removeCollisionObject(obj);
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

void Physics::addAction(btActionInterface* action)
{
    dynamicsWorld->addAction(action);
}

void Physics::removeAction(btActionInterface* action)
{
    dynamicsWorld->removeAction(action);
}
