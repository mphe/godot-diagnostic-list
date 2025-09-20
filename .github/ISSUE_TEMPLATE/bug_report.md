---
name: Bug report
about: File a bug/issue report
title: ''
labels: bug
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.

**Steps to reproduce the behavior**
A structured list of steps to consistently reproduce the behavior.

**Expected behavior**
A clear and concise description of what you expected to happen.

**Minimal reproduction project (MRP)**
If the bug is more complex than creating an empty project and installing the addon, please upload a minimal Godot project that demonstrates the bug.

**Additional context**
Add any additional information, context or screenshots about the problem here.

**System information:**
 - Operating System: 
 - Godot Version: 
 - Diagnostic List Version: 

**Log**

> [!WARNING]
> The log contains the source code of all checked scripts.
> If you do not want this, you should create an MRP first.

1. Go into `addons/diagnosticlist/utils.gd` and set `ENABLE_DEBUG_LOG = true`
2. Restart Godot
3. Reproduce the bug
4. Attach the **full** Godot log output

If the bug is a crash or freeze it might not be possible to retrieve the log from the output window.
In this case, run Godot from the command line using the following command.
The path to the project and to the Godot executable must be adapted accordingly.
A `diagnostic_log.txt` should appear in the project folder.
```sh
Godot_v4.5-stable_linux.x86_64 --editor --path <path to the project> --log-file diagnostic_log.txt
```
