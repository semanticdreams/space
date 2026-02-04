#pragma once

#include <glm/glm.hpp>
#include <vector>
#include <memory>
#include <cmath>
#include <cstdlib>

struct QuadTreeNode {
    static constexpr int CAPACITY = 1;

    glm::dvec2 center;     // center of this node
    double halfSize;       // half-length of the bounding square
    glm::dvec2 massCenter; // center of mass
    double totalMass = 0;

    std::vector<int> indices; // indices of points in this cell
    bool isLeaf = true;

    std::unique_ptr<QuadTreeNode> children[4]; // NW, NE, SW, SE

    QuadTreeNode(const glm::dvec2& center, double halfSize)
        : center(center), halfSize(halfSize), massCenter(0.0, 0.0), totalMass(0.0) {}

    bool contains(const glm::dvec2& pos) const {
        return pos.x >= (center.x - halfSize) && pos.x < (center.x + halfSize) &&
               pos.y >= (center.y - halfSize) && pos.y < (center.y + halfSize);
    }

    int getQuadrant(const glm::dvec2& pos) const {
        bool right = pos.x >= center.x;
        bool top = pos.y >= center.y;
        return (top << 1) | right; // 0=SW, 1=SE, 2=NW, 3=NE
    }

    void subdivide() {
        double qSize = halfSize / 2.0;
        for (int i = 0; i < 4; ++i) {
            double dx = (i & 1) ? qSize : -qSize;
            double dy = (i & 2) ? qSize : -qSize;
            children[i] = std::make_unique<QuadTreeNode>(center + glm::dvec2(dx, dy), qSize);
        }
        isLeaf = false;
    }

    void insert(int index, const glm::dvec2& pos, const std::vector<glm::dvec2>& positions) {
        if (!contains(pos)) return;

        // update mass
        massCenter += pos;
        totalMass += 1.0;

        if (isLeaf) {
            if (indices.size() < CAPACITY) {
                indices.push_back(index);
                return;
            } else {
                subdivide();
                for (int idx : indices)
                    insert(idx, positions[idx], positions);
                indices.clear(); // moved to children
            }
        }

        int quad = getQuadrant(pos);
        children[quad]->insert(index, pos, positions);
    }

    void finalizeMass() {
        if (totalMass > 0)
            massCenter /= totalMass;
        if (!isLeaf) {
            for (auto& child : children) {
                if (child) child->finalizeMass();
            }
        }
    }

    void computeRepulsion(
        int nodeIdx,
        const glm::dvec2& nodePos,
        glm::dvec2& force,
        const std::vector<glm::dvec2>& positions,
        double theta,
        double repulsive_constant,
        double jitter_amount = 60.0)
    {
        glm::dvec2 delta = nodePos - massCenter;
        double dist_sq = glm::dot(delta, delta) + 1e-9; // avoid division by zero
        double dist = std::sqrt(dist_sq);

        if (isLeaf) {
            for (int idx : indices) {
                if (idx == nodeIdx) continue;
                glm::dvec2 d = nodePos - positions[idx];
                double dsq = glm::dot(d, d);

                if (dsq == 0.0) {
                    d.x = ((rand() / double(RAND_MAX)) - 0.5) * jitter_amount;
                    d.y = ((rand() / double(RAND_MAX)) - 0.5) * jitter_amount;
                    force += d;
                    continue;
                }

                double rep = repulsive_constant / dsq;
                force += rep * (d / std::sqrt(dsq));
            }
        } else {
            double s = halfSize * 2.0;
            if ((s / dist) < theta) {
                double rep = repulsive_constant * totalMass / dist_sq;
                force += rep * (delta / dist);
            } else {
                for (auto& child : children) {
                    if (child) {
                        child->computeRepulsion(nodeIdx, nodePos, force, positions, theta, repulsive_constant);
                    }
                }
            }
        }
    }
};
