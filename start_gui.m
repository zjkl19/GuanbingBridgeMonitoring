function start_gui()
% start_gui  One-click launcher for the GUI from project root.
% Usage: in MATLAB (project root):  start_gui

here = fileparts(mfilename('fullpath'));
addpath(fullfile(here,'ui'));
run_gui();
end
