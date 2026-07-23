How do you pause when the song finishes??
 - add a drain callback
 - Emit a drain call with true
 - drain callback notifies that all is drained
 - (check this for correctness)

# Backends
clean up pipewire backend
Add error handling to pw audio interface.
add pulse backend

# [MPRIS](MPRIS.md)

# Database
How is the DBUS interface going to interact with the database??
Do I need my own DBUS interface??


Add properties support
Add notifications
