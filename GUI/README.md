GUI Library Documentation
A modular, frame-based GUI library for ComputerCraft (CC: Tweaked). This library allows for nested element positioning, automatic click handling, and isolated rendering contexts using windows.

1. Global Manager (manager.lua)
The Manager handles the life cycle of the GUI, including event polling and element registration.

GUI.init(config)
Starts the GUI event loop.

frames (table): An array of top-level Frame objects to manage.

onUpdate (function): A callback that runs every 0.1 seconds.

scale (number): Sets the monitor text scale (default: 0.5).

GUI.getByID(id)
Returns the element object with the matching string ID. Searches through all frames and their children.

2. UI Elements (Base Properties)
All elements inherit these properties from the base UIElement class:

id: Unique string for lookups.

x, y: Coordinates (relative to parent or monitor).

w, h: Width and Height.

bg, fg: Background and Text colors.

parent: (Optional) The window or monitor object to draw on.

3. Elements Reference
Frame (newFrame)
A container that creates a sub-window. Children added to a frame use coordinates relative to the frame's inner area.

Option	Type	Description
text	string	Title displayed on the border.
bc	color	Border color.
side	string	Border title location ("top", "bottom", "left", "right").
align	string	Title alignment ("left", "center", "right").

Export to Sheets

Methods:

addChild(element): Correctly parents an element to the frame's internal window.

Button (newButton)
A clickable rectangle with text.

Option	Type	Description
text	string	Label shown on the button.
action	function	Callback executed when clicked.
bg_active	color	Background color while being pressed.
fg_active	color	Text color while being pressed.

Export to Sheets

Label (newLabel)
A high-performance text display that only re-renders when the content changes.

Option	Type	Description
text	string	The text to display.
align	string	Horizontal alignment ("left", "center", "right").

Export to Sheets

Methods:

setText(newText): Updates the label content.

Dropdown (newDropdown)
An expandable menu for selecting from a list of options.

Option	Type	Description
options	table	List of strings to choose from.
onSelect	function	Callback f(value, index) when an option is picked.
bg_open	color	Header background color when the list is visible.
bg_list	color	Background color for unselected list items.
fg_list	color	Text color for unselected list items.
bg_sel	color	Background color for the currently highlighted item.
fg_sel	color	Text color for the currently highlighted item.

Export to Sheets

4. Coordinate Logic Summary
Top-Level Frames: x and y are relative to the monitor (1,1 is top-left).

Children in Frames: When added via frame:addChild(), the child's x=1, y=1 is the first available pixel inside the frame's border.

Layering: Ensure Dropdowns have enough space in their parent Frame to expand, as they do not currently support "floating" over multiple frames.