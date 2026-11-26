Homework 4

My source codes are located in the folder hw4.
The scenes I used to generate my outputs are located in scenes/hw4.
My own scene is located in scenes/hw4/sphere_pyramid.py.
My HW 4 outputs are in outputs/hw4.
should be a pyramid made up of six spheres with a cloth falling on top of it
uv run python main.py 4_5 scenes/hw4/sphere_pyramid.py
My custom scene's output is located in outputs/hw4/sphere_pyramid.mp4.

LLM Usage Disclosure:

- I mostly used an llm as a tutor as per usual whenever i got confused about concepts like position-based dynamics, distance constraints, signed and unsigned distance functions, collision detection, friction, and BVH traversal.
- For the cloth simulation and general mass-spring system, i asked for help understanding how a 2D grid of particles was represented in a 1D array and how CSR works. Specifically, i asked for smaller examples of how row_ptr, neighbors, and neighbor_rest relate to each other. It was a lot easier for me to understand how to iterate through the neighbors once i saw an actual example.
- For collision detection, i asked where the signed distance function for a plane came from and what the difference was between contact_margin and collision_distance. I also initially thought we were trying to find which plane the particle collided with first, so i asked the llm why we were looking for the smallest SDF and how a particle could even penetrate two planes at the same time.
- I think friction was probably the thing i struggled with the most in this homework. I kept getting confused about what the instructions meant by moving the particle back to its old position in the tangent direction. I was literally trying to multiply the old position by the tangent direction at one point lol.
- Similar to HW 3, i needed some help understanding the functions that were already provided to us, especially the functions for finding the closest point on a triangle and calculating the distance from a point to a bounding box. I also asked about why we were using unsigned distances for triangle meshes instead of signed distances while also using lecture slides as references.
- I showed the llm code i already wrote and asked it to check for small mistakes. One example was in my BVH implementation where i was still accessing mesh_triangles[triangle_index] even if triangle_index was -1.
- I used it to turn homework commands into text i could copy and paste into my terminal.
- For my custom scene, i originally wanted to simulate clothes hanging on a clothesline and blowing in the wind, but realized i was probably making things unnecessarily complicated for myself lol. I then considered making a snowman but eventually went with a pyramid of spheres with a cloth falling on top of it. I used cloth_tunnel.py and composite_collide.py as references. I could've probably gone to OH for assistance here, but i ended up asking the llm to explain the different parts of the scenes so i could understand how to make my own. 
- Overall, i worked through the main physics implementations myself and used the llm mainly for explanations and debugging feedback. 