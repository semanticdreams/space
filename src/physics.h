#pragma once

#include <btBulletDynamicsCommon.h>
#include <BulletSoftBody/btSoftRigidDynamicsWorld.h>
#include <BulletSoftBody/btSoftBody.h>
#include <BulletSoftBody/btSoftBodyHelpers.h>

class Physics {
public:
    Physics();
    ~Physics();

    void update(uint32_t);
    void setGravity(float x, float y, float z);
    void addRigidBody(btRigidBody* body);
    void removeRigidBody(btRigidBody* body);

    btSoftRigidDynamicsWorld* getWorld() const { return dynamicsWorld; }

private:
    btBroadphaseInterface *broadphase;
    btDefaultCollisionConfiguration *collisionConfiguration;
    btCollisionDispatcher *dispatcher;
    btSequentialImpulseConstraintSolver *solver;
    btSoftRigidDynamicsWorld *dynamicsWorld;
};
