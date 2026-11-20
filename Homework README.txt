My source codes are located in the folder hw3
The scenes I used to generate my outputs are located in scenes/hw3
The JSON of my own scene are in scenes/hw3/wizardtower.json
The assets involved in my rendering is in assets/water_bottle

My HW 3 outputs are in outputs/hw3

To run my rendering to see the animation (should be wizard tower with a moon at the top right):
uv run python main.py 3_6 scenes/hw3/wizardtower.json

Image stills are also saved in outputs/ for different time points.

The wizard tower model was downloaded from:
Wizard Tower by Nick Slough [CC-BY] (https://creativecommons.org/licenses/by/3.0/) via Poly Pizza (https://poly.pizza/m/fFiFJ3hdY06)

llm usage disclosure:
- I mostly used an llm as a tutor as per usual whenever i got confused about concepts like ray-sphere intersections, shadow rays, reflections (HEAVY on this topic because the idea of having rays start from different points, bounce off surfaces, and then continue in new directions was a lot for me to process at first lol), and BVH traversal. one example is when i asked why we needed EPSILON when casting shadow rays and why we couldn't just start the shadow ray directly from the surface of an object. it helped me understand how a ray could accidentally intersect the same object it started from.
- When i was stuck trying to derive the A, B, and C values for ray-sphere intersections, i asked the llm where i should start instead of asking for the answer directly. it suggested starting with the sphere equation, substituting the ray equations into it and i moved on from there.
- One thing i struggled with was understanding the different functions and code that were already provided to us. i personally have a hard time working with reading and using someone else's code, so i needed more time to read through the functions (like the intercept ones) and understand how everything connects. even after reading the homework pdf multiple times, there were still parts i didn't fully understand, so i asked the llm to explain the instructions and functions in simpler terms.
- For lighting, i asked why shadow rays use the distance to the light instead of smallest_t from the primary loop (this was figuring out which obj was the closest), and why we divide light intensity by distance squared. i think comparing primary rays and shadow rays more during lecture would have helped me understand their differences. i think this was just a brain fart on my end, cause honestly once chat explained it, it was literally so obvious why. 
- For BVH, i asked about how next_index works. i think the visual, step-by-step example of BVH traversal during lecture was really helpful during lecture because I had to rewatch the podcast when you were talking about the topic. 
- I showed it code i already wrote and asked it to check for small mistakes, especially with nested loops, and braces (this was really hard to keep track when writing my own scene).
- I also asked syntax questions about slang. for example, the llm suggested float("inf") for smallest_t, which wasn't valid in slang apparently. So, i ended up using float smallest_t = 1e30 before my primary ray for loop courtersy of chat.
- I used it to turn homework commands into text i could copy and paste into my terminal.
- For my custom scene, i asked for help converting a wizard tower model from obj to ply, choosing colors, and positioning the sun and lights. 
- I asked for help with my camera animation because it kept zooming in and out during the 360-degree rotation. i showed the llm the interpolation code, and we figured out that linear interpolation was causing the issue. basically, instead of moving in a perfect circle around the tower, the camera was taking straight-line shortcuts between keyframes, making it move closer to the tower and then farther away. i honestly didn't even consider that this could be the problem??? i ended up adding more keyframes to make the movement smoother. It suggested adding like 72 more (for more smoothness) and I absolutely was not gonna do that, but I got the gist...
- Overall, i worked through the main implementations myself and used the llm mainly for explanations and debugging feedback.