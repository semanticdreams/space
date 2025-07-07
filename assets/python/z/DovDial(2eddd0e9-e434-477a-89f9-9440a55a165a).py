import math
import operator


class DovDial:
    threshold_radius = 0.9
    dialing_threshold = 0.8

    def __init__(self):
        self.reset()

    def get_sector_4(x, y):
        y = -y
        if y >= abs(x):
            return 0
        elif -y >= abs(x):
            return 2
        elif x >= abs(y):
            return 1
        elif -x >= abs(y):
            return 3
        assert False, (x, y)

    def angle_between(angle, a, b):
        if a < b:
            return a <= angle and angle <= b
        return a <= angle or angle <= b

    def norm_angle(angle):
        return (20.0 * math.pi + angle) % (2.0 * math.pi)

    def sector_angles_8(narrowing_shift=0.1):
        #angles = [4.52, 5.3, 6.09, 0.59, 1.37, 2.16, 2.95, 3.73]
        angles = [4.32, 5.11, 5.89, 0.393, 1.1784, 1.9638, 2.7492, 3.5346]
        angles[0] += narrowing_shift
        angles[1] -= narrowing_shift
        angles[2] += narrowing_shift
        angles[3] -= narrowing_shift
        angles[4] += narrowing_shift
        angles[5] -= narrowing_shift
        angles[6] += narrowing_shift
        angles[7] -= narrowing_shift
        return angles

    def angle_from_coordinates(x, y):
        return self.norm_angle(math.atan2(y, x))

    def get_sector_8(x, y, sector_angles=None):
        sector_angles = sector_angles or self.sector_angles_8()
        angle = self.angle_from_coordinates(x, y)
        l = list(range(9))
        for i, (a, b) in enumerate(zip(l, l[1:])):
            b %= 8
            if self.angle_between(angle, sector_angles[a], sector_angles[b]):
                return i

    def test_threshold(x, y):
        return (x or y) and x**2 + y**2 > self.threshold_radius ** 2

    def angle_diff(a, b):
        """Signed difference between 2 angles."""
        f = (a - b) % math.tau
        g = (b - a) % math.tau
        return -f if f < g else g

    def reset(self):
        self.position = (0, 0)
        self.stack = []
        self.active = False
        self.dialing = False
        self.start_angle = 0
        self.reset_sector_counts()

    def reset_sector_counts(self):
        self.sector_counts = [0 for _ in range(8)]

    def dump(self):
        return {'position': self.position, 'angle': self.angle_from_coordinates(*self.position)}

    def update(self, x, y):
        self.position = (x, y)
        if test_threshold(x, y):
            angle = angle_from_coordinates(x, y)
            if not self.active:
                self.start_pos = (x, y)
                self.start_angle = angle_from_coordinates(x, y)
                self.active = True
            if not self.dialing:
                if abs(self.angle_diff(angle, self.start_angle)) > self.dialing_threshold:
                    self.stack.append(get_sector_4(*self.start_pos))
                    self.dialing = True
            if self.dialing:
                sector = get_sector_4(x, y)
                # Prevent repeated sectors & back and forth between 2 neighboring sectors
                # otherwise slightly inaccurate inputs will lead to multiple crossings of the
                # sector boundary
                if (self.stack and sector != self.stack[-1] and
                    (len(self.stack) < 2 or sector != self.stack[-2])) or not self.stack:
                    self.stack.append(sector)
            else:
                sector = get_sector_8(x, y)
                self.sector_counts[sector] += 1
        elif self.active:
            self.active = False
            if not self.dialing:
                max_sector, count = max(enumerate(self.sector_counts), key=operator.itemgetter(1))
                if count:
                    self.stack.append(max_sector)
            else:
                self.dialing = False
            self.reset_sector_counts()

