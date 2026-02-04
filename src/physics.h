#pragma once

#include <btBulletDynamicsCommon.h>

class Physics {
public:
    Physics();
    ~Physics();

    void update(uint32_t);
    void setGravity(float x, float y, float z);
    void addRigidBody(btRigidBody* body);
    void removeRigidBody(btRigidBody* body);
    void addAction(btActionInterface* action);
    void removeAction(btActionInterface* action);
    btDiscreteDynamicsWorld* getWorld() const { return dynamicsWorld; }


private:
    btBroadphaseInterface *broadphase;
    btDefaultCollisionConfiguration *collisionConfiguration;
    btCollisionDispatcher *dispatcher;
    btSequentialImpulseConstraintSolver *solver;
    btDiscreteDynamicsWorld *dynamicsWorld;
};
