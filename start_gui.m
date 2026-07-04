function start_gui()
% start_gui  One-click launcher for the GUI from project root.
% Usage: in MATLAB (project root):  start_gui

here = fileparts(mfilename('fullpath'));
addpath(here, fullfile(here,'ui'), fullfile(here,'config'), ...
    fullfile(here,'pipeline'), fullfile(here,'analysis'), ...
    fullfile(here,'scripts'), '-begin');
run_gui();
end
