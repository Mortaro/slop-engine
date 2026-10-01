# UI

Godot's UI is the checklist of what must be possible, the web is the model for how each piece behaves, and the ECS is
the shape.

## Elements are entities

A UI element is an entity with components. There is no element class and no widget hierarchy: a tree is built from
the core's `Component.Parent` (the parent's entity, so an element is despawned with its parent), and a tree's root
carries `Ui.Component.Screen`. The click counter's
tree, one bundle per element:

```
Screen    Screen, Display flex, FlexDirection column, JustifyContent center, AlignItems center, RowGap 30
├─ Title          Parent, Text
└─ CounterButton  Parent, Button, Width 176, Height 40, Display flex, centred, BackgroundImage, the game's components
   └─ CountLabel  Parent, Text, the game's CountLabel marker
```

```gdscript
# examples/click_counter/bundle/counter_button.spite
var parent = Component.Parent()
var button = Ui.Component.Button()
var width = Ui.Component.Width()
var height = Ui.Component.Height()
var display = Ui.Component.Display()
var justify = Ui.Component.JustifyContent()
var alignment = Ui.Component.AlignItems()
var background_image = Ui.Component.BackgroundImage()
var click_count = Component.ClickCount()
var primary = Component.ButtonPrimary()

func CounterButton(screen: Entity) {
    parent.entity = screen
    width.length.pixels(176.0)
    height.length.pixels(40.0)
    display.value = 'flex'
    justify.value = 'center'
    alignment.value = 'center'
    background_image.texture = "ui.button.primary.normal"
}
```

## Layout: one component per CSS property

Every CSS property the layout reads is its own component, and **a missing component means the CSS initial value**.
So an element holds only what differs from the web's defaults, and a style system can add or remove one property
without touching the others.

| Component | Values | Initial (absent) |
|---|---|---|
| `Display` | `'block'`, `'flex'`, `'grid'`, `'none'` | `'block'` |
| `GridTemplateColumns`, `GridTemplateRows` | `value`: the tracks as CSS writes them, `"100px 1fr 2fr"` (`px`, `%`, `em`, `rem`, `vw`, `vh`, `fr` or `auto`, separated by spaces, since a component holds no list) | one automatic column, implicit rows |
| `FlexDirection` | `'row'`, `'row_reverse'`, `'column'`, `'column_reverse'` | `'row'` |
| `FlexWrap` | `'no_wrap'`, `'wrap'`, `'wrap_reverse'` | `'no_wrap'` |
| `JustifyContent` | `'flex_start'`, `'flex_end'`, `'center'`, `'space_between'`, `'space_around'`, `'space_evenly'` | `'flex_start'` |
| `AlignItems` | `'stretch'`, `'flex_start'`, `'flex_end'`, `'center'`, `'baseline'` | `'stretch'` |
| `AlignSelf` | `'automatic'` plus the `AlignItems` values | `'automatic'` |
| `AlignContent` | `'stretch'`, `'flex_start'`, `'flex_end'`, `'center'`, the three spaces | `'stretch'` |
| `RowGap`, `ColumnGap` | a length | 0 |
| `FlexGrow`, `FlexShrink` | a `Float` | 0, 1 |
| `FlexBasis` | a length | automatic |
| `Order` | an `Integer` | 0 |
| `Width`, `Height` | a length | automatic |
| `MinimumWidth`, `MinimumHeight` | a length | automatic (0) |
| `MaximumWidth`, `MaximumHeight` | a length | none |
| `Padding`, `BorderWidth` | four lengths: `top`, `right`, `bottom`, `left` | 0 |
| `Margin` | four lengths, each may be automatic | 0 |
| `BoxSizing` | `'content_box'`, `'border_box'` | `'content_box'` |
| `Position` | `'normal_flow'`, `'relative'`, `'absolute'` | `'normal_flow'` (CSS `static`) |
| `Inset` | four lengths: `top`, `right`, `bottom`, `left` | automatic |
| `FontSize` | a length, the base of `em` | 16 pixels |

Enum values are renamed where the CSS word is reserved or abbreviated: `auto` is `'automatic'`, `static` is
`'normal_flow'`, `min-width` is `MinimumWidth`. `baseline` is accepted and behaves as `flex_start`.

### Lengths

`Ui.Length` is a number and a unit: `pixels`, `percent`, `em`, `root_em`, `viewport_width`, `viewport_height`,
`fraction` (CSS `fr`, for grid tracks), or `automatic`. Each length component holds one in `length` (the box ones hold four):

```gdscript
var width = Ui.Component.Width()
width.length.percent(50.0)
var margin = Ui.Component.Margin()
margin.left.automatic()
margin.right.automatic()
```

A root with an automatic height is as tall as its content, as on the web; the click counter's screen sets
`Height` to `viewport_height(100.0)` (CSS `100vh`) so its centring has the whole window to work in.

Percentages resolve against the containing block, as on the web; `viewport_*` against the root's `Ui.Component.Screen`
(`width`, `height`), which `Ui.System.FollowWindow` keeps equal to the window's client size.

### The algorithm

`Ui.System.ComputeLayout` runs in the `layout` phase (after `prepare`, before `render`). It gathers the `Parent`
links into a child list per entity, then lays out each `Screen` with a port of css-flexbox-1 §9: line breaking, resolving flexible lengths with min/max freezing, cross sizes
and stretch, auto margins, `justify-content` and `align-content` distribution, reversed axes, `order`, relative
offsets, and absolute boxes placed against the nearest positioned ancestor's padding box (at their static position
when no inset is given). `Display 'block'` children stack vertically; `'none'` removes the element and its subtree.

Leaves size to their content: `Ui.System.MeasureText` (`prepare`) writes `Ui.Component.ContentSize` for every
`Text`, and the layout uses it as the automatic size.

The result is `Ui.Component.ComputedLayout` (`left`, `top`, `width`, `height`, the border box in window pixels),
written on every element. Everything downstream reads it: the render plugin draws there, and `Ui.System.Interact`
hit-tests there.

### Tested against reference numbers

`examples/flex_layout` builds a set of flex test trees and checks every box to 0.01 pixel:
the six `justify-content` modes and overflow, grow and shrink with clamps, `align-self` and cross-axis stretch with
a maximum, centring that overflows, columns, the three reversals, `order`, relative offsets, content and border box,
auto margins, border-box `flex-basis`, absolute boxes (corners, auto-margin centring, static position, escaping to a
positioned ancestor, filling a bordered box), and wrapping with `align-content`.

```
spite flex_layout --debug-memory
```

## Grid

Godot's GridContainer, done as CSS Grid: `Display 'grid'` and a `GridTemplateColumns` holding its tracks as CSS text. Children are
placed row by row, one per cell, in `Order` then tree order; there are as many columns as tracks and as many rows as
needed (`GridTemplateRows` sizes the first ones, the rest are automatic). `ColumnGap` and `RowGap` separate them.

- A fixed track (pixels, percent of the container, em, viewport units) is that size.
- An automatic track is as wide as its widest item's max-content width, or as tall as its tallest item at that
  column's width.
- The space left over goes to `fraction` tracks in proportion (`1fr 2fr` takes a third and two thirds); with no
  fraction tracks, it is shared equally by the automatic tracks (CSS's `normal` distribution stretches them).
  Rows only share space when the container's height is definite.
- An item fills its cell unless it has its own `Width` or `Height`; margins, padding, borders, `box-sizing`,
  relative offsets and min/max apply as in flex. Absolute children are placed as in flex.
- A grid with an automatic width is as wide as its tracks' max-content widths plus gaps.

`flex_layout` checks fixed and fractional columns with gaps, automatic tracks sharing free space, and a grid's
max-content width. Items are auto-placed only: there is no `grid-column`, `grid-row` or `grid-template-areas`.

## Scrolling and clipping

Godot's ScrollContainer and `clip_contents`, done the web's way: overflow is a property of any element.

| Component | Values | Meaning |
|---|---|---|
| `OverflowX`, `OverflowY` | `'visible'` (initial), `'hidden'`, `'scroll'`, `'automatic'` | anything but `'visible'` clips that axis to the padding box and makes the element scrollable |
| `ScrollPosition` | `left`, `top` | the scroll offset (the DOM's `scrollLeft`/`scrollTop`); added by the layout when missing, and a game may set it |
| `ScrollRange` | `horizontal`, `vertical` | how far it can scroll, written by the layout: the children's extent plus the end padding, minus the padding box |
| `ComputedClip` | `left`, `top`, `right`, `bottom` | the rectangle an element is drawn and hit-tested within, written by the layout for every element (unclipped is ±10⁹) |

The layout shifts a scrolling element's children by its scroll offset. For a positioned scrolling element, its
absolute descendants' containing block moves with them, as on the web. Clips intersect down the tree.

- **Drawing.** Every draw-list rectangle carries its clip in integer pixels. The software canvas limits its loops
  to it, and the Vulkan fragment shader discards pixels outside it with the same test (`x ≥ left`, `x < right`), so
  `render_parity` still matches every pixel. It checks one both ways: beside its clipped panel it sees the clear
  colour, and inside it the plate.
- **Wheel.** `Input.Component.Mouse.wheel` is this tick's notches (positive away from the user).
  `Ui.System.Scroll` (`after_input`) moves the smallest scrollable element under the pointer that can move, 40 pixels
  a notch, vertically if it can, clamped to its range.
- **Hit testing.** `Ui.System.Interact` only hovers what is inside its clip, so a button scrolled out of view
  cannot be clicked.

- **Scrollbars.** Overlay bars (they take no layout space, like macOS and mobile), inside the padding box's right
  and bottom edges. `'scroll'` always shows one, and `'automatic'` shows one when there is somewhere to scroll.
  `ScrollbarWidth` (`'automatic'` 8 px, `'thin'` 4 px, `'none'`) and `ScrollbarColor` (`thumb`, `track`) are the CSS
  properties of the same names. The layout writes `ComputedScrollbars` (the bars' thickness and paint order) and,
  for each bar that is shown, a `VerticalScrollbar` or `HorizontalScrollbar` holding its track and thumb geometry; a
  bar that is not shown has no component. Dragging a thumb (`Ui.Component.ScrollDrag` while the button is held, with
  the marker `DraggingVertical` for the vertical bar) scrolls proportionally, and a press on a scrollbar never reaches
  the element under it. An absolute element is clipped by every clipping ancestor.

`examples/scroll_list` is a 200 × 200 list of 20 clickable rows; `examples/scroll_list_test` scrolls it two notches
with real `WM_MOUSEWHEEL` messages, clicks a row, then drags the thumb, and checks the offset, the rows' new
positions, that the click landed on the row now under the pointer, and that grabbing the thumb clicked nothing.

## Focus and text input

Godot's LineEdit, or the web's `<input>`, as components:

| Component | Meaning |
|---|---|
| `Focusable` | marker: a click can focus it |
| `Focused` | marker: it has keyboard focus. `Ui.System.Focus` gives it to the topmost focusable element under a press (a press on nothing focusable blurs), and Tab / Shift+Tab move it to the next / previous focusable element in tree order, wrapping around |
| `TextInput` | `value`: the text being edited |
| `Caret` | `index`: where typing goes, from 0 to the value's length |

`Ui.System.EditText` (`after_input`) edits the focused `TextInput`. It replays this tick's keystrokes in the order
they happened (the tick's key-pressed and character-typed event entities, sorted by id, since the window thread can
deliver several frames' worth of input in one tick), so Backspace, Delete, Left, Right, Home and End apply exactly
where they were typed, and it mirrors the value into the element's `Text`. `DrawUi` draws the
focused element's caret after its text. Keyboard state is key entities, children of the window: `Input.Component.Key`
(`code`, a virtual key) while it is held, marked `JustPressed` on the tick it went down; characters arrive as
`character_typed` events (from `WM_CHAR`). `Input.Key` names the virtual keys.

`examples/text_field` is a form with two fields. `examples/text_field_test` clicks the first, types "HELLO",
presses Backspace and Left twice, types "X", presses Tab, types "Y", and checks "HEXLL" (caret 3) in the first and
"Y" in the second, which now has focus.

## Paint order

Elements are painted in tree order, parent before children, as on the web, by one system, `Render.System.DrawUi`:
each element's background colour, background image, then text; an element's scrollbars come after all of its
descendants. After layout, a paint pass numbers them (`ComputedLayout.order`, `ComputedScrollbars.order`), visiting
each element's children stable-sorted by `Ui.Component.ZIndex` (`value`, 0 when absent), so a higher z paints later
and its whole subtree comes with it, as a stacking context does; a negative z paints under its siblings. An element
the layout didn't reach this frame (`display: none`, or no longer attached) has order −1 and isn't painted.
Simplified from CSS: z-index applies to any element, and there are no separate paint phases for positioned and
in-flow boxes.

## Pointer markers

`Ui.Component.Button` is a marker that makes an element pressable. `Ui.System.Interact` (`after_input`) owns three
more markers:

| Component | Meaning |
|---|---|
| `Ui.Component.Hovered` | the mouse is over it |
| `Ui.Component.Pressed` | a press started on it and is held |
| `Ui.Component.Clicked` | a press was released over it, this tick |
| `Ui.Component.RightPressed` | a right press started on it and is held |
| `Ui.Component.RightClicked` | a right press was released over it, this tick |
| `Ui.Component.DoubleClicked` | a double click landed on it, this tick (its two clicks are `Clicked` too, as on the web) |

A press only counts when it starts inside the button, and a click only when it also ends inside, so dragging off a
pressed button cancels it, as on the web. `Clicked` is removed on Interact's next run, so every system sees a click
once.

## Drag and drop

Add `Ui.Component.Draggable` to an element that can be picked
up and `Ui.Component.DropTarget` to one that accepts drops. `Ui.System.Interact` owns the rest:

| Component | On | Meaning |
|---|---|---|
| `Ui.Component.DragPress` | a draggable | pressed, not moved yet (`left`, `top`, and `grab_left`, `grab_top` inside the element) |
| `Ui.Component.Dragging` | a draggable | moved more than 4 px while held: a drag is on (`grab_left`, `grab_top`) |
| `Ui.Component.DragOver` | a drop target | the topmost target under the pointer while something is dragged |
| `Ui.Component.Dropped` | a drop target | released over it, this tick; `source` is the dragged entity's id |
| `Ui.Component.DropMissed` | a draggable | released over no target, this tick |

- The topmost target is the one painted last (highest `ComputedLayout.order`); a draggable is never its own target.
- A drag is never a click: the tick a drag ends gives no element a `Clicked`, neither the element it started on
  nor a `Button` around it, so an
  element can be both a `Button` and `Draggable`, as an inventory slot is.
- `Dropped` and `DropMissed` are removed on Interact's next run, as `Clicked` is.
- The dragged element stays where it is. A game shows what it carries by spawning its own element, positioned from
  `Input.Component.Mouse` and `Dragging`'s grab offset, with a high `ZIndex`, and despawning it when `Dragging` goes.

```gdscript
type Slot {
    dropped: Ui.Component.Dropped
    bench_slot: Component.BenchSlot
}

func update_each(slot: Slot) {
    var item = Lookup<Component.InventoryItem>().of(slot.dropped.source)
    assert item
    slot.bench_slot.item = item.kind
}
```

Tested by `examples/drag_drop_test`: a drag onto a target, a drag onto nothing and a plain click on the same
element, driving the real window with posted mouse messages, each step waiting for the marker it causes.

## Combo box

A combo box is four bundles and one system, `Ui.System.Choose` (`update`):

```gdscript
var box = world.create_entity_from_bundle(Ui.Bundle.ComboBox(panel))
world.create_entity_from_bundle(Ui.Bundle.ComboLabel(box, "Choose"))
var popup = world.create_entity_from_bundle(Ui.Bundle.ComboPopup(box))
world.create_entity_from_bundle(Ui.Bundle.ComboOption(popup, 0, "First"))
world.create_entity_from_bundle(Ui.Bundle.ComboOption(popup, 1, "Second"))
```

(each bundle built into a variable first, as Spite wants). The box is a `Button` with
`Ui.Component.ComboBox { selected }`; the popup is positioned absolutely under it (`top: 100%`, `z-index: 100`)
and hidden (`display: none`) until the box is clicked. Choose then:

- gives the box `Ui.Component.ComboOpen` and shows the popup (`display: flex`, a column);
- on a click on an option, sets `ComboBox.selected` to its `ComboOption.index`, puts its text in the box's
  `ComboLabel`, closes the popup and gives the box `Ui.Component.SelectionChanged` until Choose's next run;
- closes it on any other click, on the box or anywhere else.

Style the parts with the usual components on the same entities. Tested by `examples/combo_box_test`.

**An element with text is a leaf.** `Text` (and any `ContentSize`) makes an element's size come from its content,
and its children would get no layout, so an element with text that has children crashes the layout. Put the text
on a child, as `ComboLabel` and the click counter's `CountLabel` do.

## Reacting to a click

Ask for the marker. The count label is a child entity, so the system takes two rows and the game's own
`CountLabel` marker picks the right one:

```gdscript
# examples/click_counter/system/count_clicks.spite
type ClickedCounter {
    clicked: Ui.Component.Clicked
    click_count: Component.ClickCount
}

type CountText {
    label: Component.CountLabel
    text: Ui.Component.Text
}

func update_each(counter: ClickedCounter, shown: CountText) {
    counter.click_count.clicks = counter.click_count.clicks + 1
    shown.text.text = "{counter.click_count.clicks}"
}
```

## Styles are components

Each style property is its own component too. The render plugin draws whatever has them, so a style only needs to
be set to show. A game writes its state styles as systems, the way a stylesheet writes `:hover`:

```gdscript
# examples/click_counter_theme_plugin/theme/system/style_hovered_button.spite
type HoveredButton {
    hovered: Added<Ui.Component.Hovered>
    image: Ui.Component.BackgroundImage
    primary: Component.ButtonPrimary
}

func update_each(button: HoveredButton) {
    button.image.texture = "ui.button.primary.hover"
}
```

The click counter's four:

| System | Row | Sets |
|---|---|---|
| `HoveredButton` | `Added<Hovered>` | `ui.button.primary.hover` |
| `UnhoveredButton` | `Removed<Hovered>` | `ui.button.primary.normal` |
| `PressedButton` | `Added<Pressed>` | `ui.button.primary.pressed` |
| `ReleasedButton` | `Removed<Pressed>`, `Hovered` | `ui.button.primary.hover` |

`Component.ButtonPrimary` is the game's own marker; it plays the part of a CSS class.

| Style | Meaning |
|---|---|
| `BackgroundColor` | a colour filling the border box |
| `BackgroundImage` | a texture asset id stretched over the border box |
| `Text` | text, its scale and colour, drawn at the content box |

## Fonts

Text draws in the built-in 5×7 bitmap font unless its entity also has a `Ui.Component.Font { name, face, size }`:
`name` is the id of a font file cooked into the cache (a `.ttf`, or a `.ttc` with `face` choosing the face), `size` is
in pixels.

```gdscript
var font = Ui.Component.Font()
font.name = "font.gulim"
font.size = 12
label.add_component(font)
```

- **The font cache is a resource, each size an entity.** `Ui.Fonts()` (a singleton) loads a face the first time a
  size of it is asked for and keeps the faces by name (a `TrueType.Face` cannot be made without its bytes, so it is
  not a component). Each face and size gets an entity holding `Ui.Component.GlyphAtlas`: its metrics, the atlas
  texture and texels, the shelf packer, and its glyph table (`Ui.GlyphTable`, the atlas's own data: code to glyph,
  each glyph's rectangle and bearing, and the codes queued). It measures text from the font's advances (so layout is right on the first frame), and
  rasterises glyphs anti-aliased with the standalone `spite_truetype` package
  (`D:/Projects/spite_truetype`, loaded by `ui/ui.spite`).
- **Glyphs are made on demand**, 32 per frame at most, into a 1024² atlas per face and size, like Unreal's Slate font
  cache: a character seen for the first time is drawn from the next frame. `PendingGlyphs` and `AtlasChanged` markers
  on the atlas's entity make the rasterising and publishing systems run only for the sizes that have work.
- **Drawing.** `DrawUi` lays glyph quads along a pen from the baseline; each is a draw-list image with a texel source
  rectangle into the atlas and the text's colour as tint, drawn the same by Vulkan and the software rasteriser
  (`render_parity`).
- **Waiting for text in a test:** `fonts.settled()` is true once no face is loading, no glyph is queued and no atlas
  waits for upload.

## Images are asset ids

A `BackgroundImage` names an asset id that a recipe produced, never a file path or a rectangle, so repainting the
PSD changes the game and moving a layer changes nothing. Loading is the engine's job; see
[assets-and-recipes.md](assets-and-recipes.md#background-loading).

---

Next: [Rendering](rendering.md), how the draw list becomes a frame.
