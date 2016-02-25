{application, sendfile,
 [{description, "sendfile linked-in driver"},
  {vsn, "1.2"},
  {modules,
   [
    sendfile,
    sendfile_app,
    sendfile_sup
   ]},
  {applications,
   [
    kernel,
    stdlib
   ]},
  {registered, [sendfile]},
  {mod, {sendfile_app, []}},
  {env, []}
 ]}.
