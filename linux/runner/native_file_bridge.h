#ifndef BLANKO_NATIVE_FILE_BRIDGE_H_
#define BLANKO_NATIVE_FILE_BRIDGE_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// The window owns the channels and cancels outstanding work when destroyed.
void blanko_register_native_file_bridge(GtkWindow* window, FlView* view);

#endif  // BLANKO_NATIVE_FILE_BRIDGE_H_
