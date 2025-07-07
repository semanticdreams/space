import bullet as bt

print('bullet from python...')

collision_configuration = bt.DefaultCollisionConfiguration()
dispatcher = bt.CollisionDispatcher(collision_configuration)
broadphase = bt.DbvtBroadphase()
solver = bt.SequentialImpulseConstraintSolver()

dynamics_world = bt.SoftRigidDynamicsWorld(dispatcher, broadphase, solver, collision_configuration)
dynamics_world.setGravity(bt.Vector3(0, -9.8, 0))

# ground
ground_shape = bt.StaticPlaneShape(bt.Vector3(0, 1, 0), 1)
ground_motion_state = bt.DefaultMotionState(bt.Transform(bt.Quaternion(0, 0, 0, 1),
                                                         bt.Vector3(0, -1, 0)))
ground_body = bt.RigidBody(bt.RigidBodyConstructionInfo(0, ground_motion_state, ground_shape,
                                                        bt.Vector3(0, 0, 0)))
dynamics_world.addRigidBody(ground_body)

shape = bt.BoxShape(bt.Vector3(1, 1, 1))  # A 2x2x2 box
mass = bt.Scalar(1.0)
position = bt.Vector3(0, 10, 0)  # Start at height 10
motion_state = bt.DefaultMotionState(bt.Transform(bt.Quaternion(0, 0, 0, 1), position))
inertia = bt.Vector3(0, 0, 0)  # Zero inertia by default
shape.setLocalScaling(bt.Vector3(1, 1, 1))  # Set scale of the shape
shape.calculateLocalInertia(mass, inertia)
body_info = bt.RigidBodyConstructionInfo(mass, motion_state, shape, inertia)
body = bt.RigidBody(body_info)
dynamics_world.addRigidBody(body)

time_step = bt.Scalar(1.0 / 60.0) # use delta
fixed_time_step = bt.Scalar(1.0 / 60.0)

print(body.getPosition().getOrigin())

for i in range(300):  # Simulate for 300 frames (5 seconds)
    dynamics_world.stepSimulation(time_step, 1, fixed_time_step)

t = bt.Transform()
body.getMotionState().getWorldTransform(t)
print(t.getOrigin())

dynamics_world.removeRigidBody(ground_body)
dynamics_world.removeRigidBody(body)
