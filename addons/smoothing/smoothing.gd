#	Copyright (c) 2019 Lawnjelly
#
#	Permission is hereby granted, free of charge, to any person obtaining a copy
#	of this software and associated documentation files (the "Software"), to deal
#	in the Software without restriction, including without limitation the rights
#	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#	copies of the Software, and to permit persons to whom the Software is
#	furnished to do so, subject to the following conditions:
#
#	The above copyright notice and this permission notice shall be included in all
#	copies or substantial portions of the Software.
#
#	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#	SOFTWARE.

extends Spatial

export (NodePath) var target: NodePath setget set_target, get_target

var _m_Target: Spatial

var _m_trCurr: Transform
var _m_trPrev: Transform

const SF_ENABLED = 1 << 0
const SF_TRANSLATE = 1 << 1
const SF_BASIS = 1 << 2
const SF_SLERP = 1 << 3
const SF_DIRTY = 1 << 4
const SF_INVISIBLE = 1 << 5

export (int, FLAGS, "enabled", "translate", "basis", "slerp") var flags: int = SF_ENABLED | SF_TRANSLATE | SF_BASIS setget _set_flags, _get_flags

##########################################################################################
# USER FUNCS

# Call this on e.g. starting a level, AFTER moving the target
# so we can update both the previous and current values.
func teleport() -> void:
	var temp_flags = flags
	flags |= SF_TRANSLATE | SF_BASIS

	_refresh_transform()
	_m_trPrev = _m_trCurr

	# Do one frame update to make sure all components are updated.
	_process(0)

	# Resume old flags.
	flags = temp_flags


func set_enabled(p_enable: bool):
	if p_enable:
		flags |= SF_ENABLED
	else:
		flags &= ~SF_ENABLED
	_set_processing()


func is_enabled() -> bool:
	return (flags & SF_ENABLED) == SF_ENABLED

##########################################################################################

func _ready():
	_m_trCurr = Transform()
	_m_trPrev = Transform()


func set_target(new_value):
	target = new_value
	if is_inside_tree():
		_find_target()


func get_target():
	return target


func _set_flags(new_value):
	flags = new_value
	# We may have enabled or disabled.
	_set_processing()


func _get_flags():
	return flags


func _set_processing():
	var bEnable := (flags & SF_ENABLED) == SF_ENABLED
	if (flags & SF_INVISIBLE) == SF_INVISIBLE:
		bEnable = false

	set_process(bEnable)
	set_physics_process(bEnable)


func _enter_tree():
	# The node might have been moved.
	_find_target()


func _notification(what: int) -> void:
	match what:
		# Invisible turns off processing.
		NOTIFICATION_VISIBILITY_CHANGED:
			if is_visible_in_tree():
				flags &= ~SF_INVISIBLE
			else:
				flags |= SF_INVISIBLE

			_set_processing()


func _refresh_transform() -> void:
	flags &= ~SF_DIRTY

	if not _has_target():
		return

	_m_trPrev = _m_trCurr
	_m_trCurr = _m_Target.transform


func _IsTargetParent(node: Node) -> bool:
	if node == _m_Target:
		return true   # Disallow.

	var parent: Node = node.get_parent()
	if parent:
		return _IsTargetParent(parent)

	return false


func _find_target():
	_m_Target = null
	if target.is_empty():
		return

	var targ := get_node(target)

	if not targ:
		push_error("SmoothingNode : Target " + target + " not found")
		return

	if not targ is Spatial:
		push_error("SmoothingNode : Target " + target + " is not inheriting Spatial")
		target = ""
		return

	# If we got to here, `targ` is a Spatial.
	_m_Target = targ

	# Do a final check.
	# Is the target a parent or grandparent of the smoothing node?
	# Ff so, disallow.
	if _IsTargetParent(self):
		var msg := _m_Target.get_name() + " assigned to " + self.get_name() + "]"
		push_error("SmoothingNode : Target should not be a parent or grandparent [" + msg)

		_m_Target = null
		target = ""
		return


func _has_target() -> bool:
	if _m_Target == null:
		return false

	# Has not been deleted?
	if is_instance_valid(_m_Target):
		return true

	_m_Target = null
	return false


func _process(_delta: float) -> void:
	if (flags & SF_DIRTY) == SF_DIRTY:
		_refresh_transform()

	var f = Engine.get_physics_interpolation_fraction()

	var tr: Transform = Transform()

	# translate
	if (flags & SF_TRANSLATE) == SF_TRANSLATE:
		var ptDiff = _m_trCurr.origin - _m_trPrev.origin
		tr.origin = _m_trPrev.origin + (ptDiff * f)

	# rotate
	if (flags & SF_BASIS) == SF_BASIS:
		if (flags & SF_SLERP) == SF_SLERP:
			tr.basis = _m_trPrev.basis.slerp(_m_trCurr.basis, f)
		else:
			var res := Basis()
			res.x = _m_trPrev.basis.x.linear_interpolate(_m_trCurr.basis.x, f)
			res.y = _m_trPrev.basis.y.linear_interpolate(_m_trCurr.basis.y, f)
			res.z = _m_trPrev.basis.z.linear_interpolate(_m_trCurr.basis.z, f)
			tr.basis = res

	transform = tr


func _physics_process(_delta: float) -> void:
	# Take care of the special case where multiple physics ticks
	# occur before a frame... the data must flow!
	if (flags & SF_DIRTY) == SF_DIRTY:
		_refresh_transform()

	flags |= SF_DIRTY
