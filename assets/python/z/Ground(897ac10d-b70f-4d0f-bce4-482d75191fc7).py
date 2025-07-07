class Ground:
    def __init__(self):
        self.ground_shape = bt.StaticPlaneShape(bt.Vector3(0, 1, 0), 1)
        self.ground_motion_state = bt.DefaultMotionState(bt.Transform(bt.Quaternion(0, 0, 0, 1),
                                                                 bt.Vector3(0, -90, 0)))
        self.ground_body = bt.RigidBody(bt.RigidBodyConstructionInfo(
            0, self.ground_motion_state, self.ground_shape,
            bt.Vector3(0, 0, 0))
        )

        self.terrain = z.PerlinTerrain()
        self.terrain_triangle_mesh, self.terrain_shape, self.terrain_motion_state, self.terrain_body = self.terrain.get_physics()
        world.physics.addRigidBody(self.terrain_body)


        ## box
        self.shape = bt.BoxShape(bt.Vector3(1, 1, 1))  # A 2x2x2 box
        mass = bt.Scalar(1.0)
        position = bt.Vector3(0, 10, 0)  # Start at height 10
        self.motion_state = bt.DefaultMotionState(bt.Transform(bt.Quaternion(0, 0, 0, 1), position))
        inertia = bt.Vector3(0, 0, 0)  # Zero inertia by default
        self.shape.setLocalScaling(bt.Vector3(1, 1, 1))  # Set scale of the shape
        self.shape.calculateLocalInertia(mass, inertia)
        body_info = bt.RigidBodyConstructionInfo(mass, self.motion_state, self.shape, inertia)
        self.body = bt.RigidBody(body_info)
        world.physics.addRigidBody(self.body)

        self.rectangles = z.Rectangle(color=(0, 1, 0,1)) * 6
        self.cuboid = z.Cuboid([x.layout for x in self.rectangles])
        self.cuboid.layout.size = np.array((10, 10, 10))

        world.updated.connect(self.update)

    def update(self, delta):
        t = bt.Transform()
        self.body.getMotionState().getWorldTransform(t)
        self.cuboid.layout.position = t.getOrigin().to_numpy()
        self.cuboid.layout.rotation = t.getRotation().to_numpy()
        self.cuboid.layout.layouter()

    def drop(self):
        world.updated.disconnect(self.update)
        self.cuboid.drop()
        [x.drop() for x in self.rectangles]
        world.physics.removeRigidBody(self.body)
        world.physics.removeRigidBody(self.ground_body)
        self.terrain.drop()