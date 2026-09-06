# computercraft-scripts

## turtles/sweeper.lua

Patrols a flat area picking up loose item drops and stashing them in a chest.

```
wget https://raw.githubusercontent.com/erinlkolp/computercraft-scripts/refs/heads/main/turtles/sweeper.lua
```

## turtles/flattener.lua

Levels a 15x15 area down to the elevation the turtle is started at, hauling
everything it mines back to a chest placed directly behind it. Nothing at or
below the starting layer is touched.

```
wget https://raw.githubusercontent.com/erinlkolp/computercraft-scripts/refs/heads/main/turtles/flattener.lua
```

## Tests

`test/fake_turtle.lua` stubs the CC turtle API over a toy voxel world so the
scripts can be exercised without a server. From the repo root:

```
lua test/flattener_test.lua
```
