class FlatGround:
    def __init__(self):
        # Use only a static plane for physics — no terrain mesh needed
        self.ground_shape = bt.StaticPlaneShape(bt.Vector3(0, 1, 0), 0)  # y=0
        self.ground_motion_state = bt.DefaultMotionState(bt.Transform(
            bt.Quaternion(0, 0, 0, 1), bt.Vector3(0, -100, 0)))
        self.ground_body = bt.RigidBody(bt.RigidBodyConstructionInfo(
            0, self.ground_motion_state, self.ground_shape,
            bt.Vector3(0, 0, 0))
        )
        world.physics.addRigidBody(self.ground_body)

        # Flat visual terrain only, not used for physics
        self.terrain = z.FlatTerrain()

        # Falling test box
        self.shape = bt.BoxShape(bt.Vector3(1, 1, 1))
        mass = bt.Scalar(1.0)
        position = bt.Vector3(0, -90, 0)
        self.motion_state = bt.DefaultMotionState(bt.Transform(bt.Quaternion(0, 0, 0, 1), position))
        inertia = bt.Vector3(0, 0, 0)
        self.shape.setLocalScaling(bt.Vector3(1, 1, 1))
        self.shape.calculateLocalInertia(mass, inertia)
        body_info = bt.RigidBodyConstructionInfo(mass, self.motion_state, self.shape, inertia)
        self.body = bt.RigidBody(body_info)
        world.physics.addRigidBody(self.body)

        # Visual box
        self.rectangles = z.Rectangle(color=(0, 1, 0, 1)) * 6
        self.cuboid = z.Cuboid([x.layout for x in self.rectangles])
        self.cuboid.layout.size = np.array((10, 10, 10))

        world.updated.connect(self.update)

    def update(self, delta):
        t = bt.Transform()
        self.body.getMotionState().getWorldTransform(t)
        o = t.getOrigin()
        self.cuboid.layout.position = np.array((o.x(), o.y(), o.z()))
        r = t.getRotation()
        self.cuboid.layout.rotation = np.array((r.w(), r.x(), r.y(), r.z()))
        self.cuboid.layout.layouter()

    def drop(self):
        world.updated.disconnect(self.update)
        self.cuboid.drop()
        [x.drop() for x in self.rectangles]
        world.physics.removeRigidBody(self.body)
        world.physics.removeRigidBody(self.ground_body)
        self.terrain.drop()
