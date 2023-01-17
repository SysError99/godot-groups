# QGodot
Advanced yet simple node querying library for Godot. Resembles a lot with Entity Component System (ECS) architecture.

---

## Disclaimer
This addon will NOT address any of performance benefits, unlike many of ECS libraries that claim to have. This project is made for purely programming aesthetics only. However, unlike other GDScript-based ECS libraries, this project offers ECS-like programming experience with very comparable performance against traditional OOP programming in GDScript.

---

## Quickstart
Import `q_godot.gd` into AutoLoad in your project as any of names you want, `QGodot` will be a default name.

![image](https://user-images.githubusercontent.com/17522480/212733830-72a3cc8e-e028-4299-9acc-cb9f8ffe83f2.png)

Then, setup nodes that will be controlled by our first system. In this case, we will have `KinematicBody2D` node that has an `Icon` node inside:

![image](https://user-images.githubusercontent.com/17522480/212737269-fe81e97d-011f-4bd9-b9c0-1bb5515d35b6.png)

Now we can have our first system that will control three nodes. First, create a script that binds to our game scene. In this case, we will keep it simple by attaching a new script to parent node of the scene:

![image](https://user-images.githubusercontent.com/17522480/212734669-fdf68bf6-7db4-440f-9306-254e4a719ffb.png)

Let's 'subscribe' to our first query!:

```gdscript
extends Node2D

# First element in the query will be 'main class name' of parent node.
onready var query := QGodot.query(["KinematicBody2D"])
```

Now we can iterate through our subscribed query in `_process()` :

```gdscript
const TARGET = Vector2(512,300)

func _process(_delta: float) -> void:
    for entity in query:
		var vel := (entity.position.direction_to(TARGET) * 10.0) as Vector2
		entity.move_and_slide(vel)
		entity.look_at(TARGET)
```

The rest of code should be something like this:

![image](https://user-images.githubusercontent.com/17522480/212868982-3918b69c-7f66-40a5-a8a0-cd91be2359c9.png)

When you start running the game, voila!

![image](https://user-images.githubusercontent.com/17522480/212736180-a8f69a45-ba88-4159-87ef-dba16b5f130b.png)

Now, we wanted constantly scale icon size by making changes on the `Icon` node. Let's make change on the query and add one more node to query:

```gdscript
# Unlike first element, you need to add node names next to first element, NOT the main class name.
onready var query := QGodot.query(["KinematicBody2D", "Icon"])
```

Then, on the `_process()` loop, we can retrieve component by using `get_meta()` on the entity node:

```gdscript
func _process(_delta: float) -> void:
    for entity in query:
        # Whnh querying by 'get_meta()', you must add dollar sign ('$') in front of node name.
        var icon := entity.get_meta("$Icon") as Sprite
        icon.scale = icon.scale * 1.01
```

The rest of code now should be something like this:

![image](https://user-images.githubusercontent.com/17522480/212878427-64c624a9-2e04-46e8-95ae-aa7972c76fad.png)

When we start the project again, the icon now scales indefinitely!

![image](https://user-images.githubusercontent.com/17522480/212738843-e2db606d-1c83-4f79-b335-f7a972cc3d5a.png)

---

## Quickstart (C#)
Importing is similar to GDScript variant, but instead it will be `QGodotSharp.cs` for script, and `QGodotSharp` for class.

Unlike GDScript, C# version utilises C#'s `Tuple` to query nodes. Again, first element will always be class reference of parent node:

```cs
public override void _Ready()
{
    await ToSignal(GetTree(), "idle_frame"); // On '_Ready()', it must wait at least one frame before query can occur
    foreach (var (parent, sprite) in QGodotSharp.Query<KinematicBody2D, Sprite>())
    {
        sprite.Scale = Vector2.One * 4f;
    }
}
public override void _Process(float delta)
{
    foreach (var (parent, sprite) in QGodotSharp.Query<KinematicBody2D, Sprite>())
    {
        var vel = parent.Position.DirectionTo(Target) * 10;
        parent.MoveAndSlide(vel);
        parent.LookAt(Target);
    }
    _label.Text = "FPS: " + Engine.GetFramesPerSecond();
}
```

---

## Changing Scene
This addon heavily relies on proper singal bindings and node setups, thus require its own function to change scenes.

```gdscript
QGodot.change_scene("res://target_scene.tscn")
```

```cs
QGodotSharp.ChangeScene("res://target_scene.tscn");
```

---

## Registering Node As Scene Root
By default, current scene will be a node that will be scanned, but sometimes you wanted the addon to only scan through specified nodes. There are two ways to handle it.

First is to add the node into `registered_scene` group.

![image](https://user-images.githubusercontent.com/17522480/212744832-99470db1-b5cb-4895-849c-509ac744e41a.png)

Second, is by code:

```gdscript
QGodot.register_as_scene(my_target_node)
```

```cs
QGodotSharp.RegisterAsScene(myTargetNode);
```

---

## One-shot Query Binding (GDScript Only)
Sometimes you don't really want to iterate all nodes in every given frame, such as, you wanted to do event-driven programming (using `Signal`), you can do one-shot binding instead:

```gdscript
QGodot.bind_query(
    ["KinematicBody2D", "Icon"]
    self, # Target object to bind (in this case, this script)
    "entity_entered" # Function name to bind
)


# In this case, naming is no longer a concern. However, it still needs to be in proper order, and first argument is still a parent node.
func entity_entered(parent: KinematicBody2D, icon: Sprite) -> void:
    var tween := $Tween as Tween
    icon.scale = Vector2.ONE * 4
    tween.interpolate_property(
        parent, "position",
        parent.position, Vector2(512, 300),
        60
    )
    tween.start()
```

---

## Current Scene Query Binding (GDScript Only)
Sometimes, you don't really want all systems in the game to run all the time in all scenes. You can instead bind query using `bind_query_to_current_scene()`:

```gdscript
QGodot.bind_query_to_current_scene(
    ["KinematicBody2D", "Icon"],
    self,
    "entity_entered"
)
```

---

## Using Godot Groups In Query (GDScript Only)
You can also add 'groups' into the query if you wanted to have better node filtering However, first element in the query array still needs to be main class name of parent node.

Example, querying `KinematicBody2D` with `Sprite` node named 'Icon', in the group 'enemy':

```gdscript
onready var query := QGodot.query(["KinematicBody2D", "Icon", "enemy"])
```

---

## Binding Query With Instantiable References (GDScript Only)
Sometimes you wanted to iterate through nodes but using instantiable classes. This will slightly helps on speed since it doesn't require constant use of `get_meta()` to get sub nodes. However, this will increase memory usage, and is slightly tricky to use.

*Note: when querying, variable bindings will use `snake_case`. Two variables `parent`, and `shared` will be reserved for parent node binding and shared variable binding repectively.*

Which means, `QGodot.bind_query()` will help us in this case.


```gdscript
extends Node
var count := 0


func _ready() -> void:
	QGodot.bind_queqy(
		["KinematicBody2D", "Icon"], # Node list. Use 'PascalCase' for every nodes,
		# including main class name of first parameter in the query array, in exception for 'groups',
		# which still can be 'snake_case'.
		Movement,
		self # Use this instance as shared object for this query.
	)


class Movement extends Node:
	const TARGET = Vector2(512, 300)
	
	# Reserved keywords
	var parent: KinematicBody2D
	var shared: Node
	
	# Node names, will be converted to 'snake_case'!
	# Example 1: node name is 'SomeGoodStatus', it will be converted to 'some_good_states'.
	# Example 2: node name is 'Node2D', 'it will be converted to 'node_2d'.
	# In this case, node name is 'Icon', which means, it will be converted to just 'icon'.
	var icon: Sprite
	
	func _ready() -> void:
		shared.count += 1
	
	func _process(_delta: float) -> void:
		var vel := (parent.position.direction_to(TARGET) * 10.0) as Vector2
 		parent.move_and_slide(vel)
 		parent.look_at(TARGET)
 		sprite.scale *= 1.001
```
