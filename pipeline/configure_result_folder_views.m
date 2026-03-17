function configure_result_folder_views(root_dir, cfg)
% configure_result_folder_views  Best-effort Explorer view setup for result folders.
%   On Windows 10/11, scans root_dir for folders containing .jpg/.emf/.fig and
%   applies large-icon + group-by-type folder view settings using PowerShell.

    if nargin < 1 || isempty(root_dir) || ~ispc || ~exist(root_dir, 'dir')
        return;
    end
    if nargin < 2
        cfg = struct();
    end
    if ~should_configure_views(cfg)
        return;
    end

    proj_root = fileparts(fileparts(mfilename('fullpath')));
    script_path = fullfile(proj_root, 'scripts', 'set_result_folder_view.ps1');
    if exist(script_path, 'file') ~= 2
        warning('Folder view script not found: %s', script_path);
        return;
    end

    cmd = sprintf(['powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass ', ...
        '-File "%s" -RootDir "%s" -CloseNewWindows'], ...
        strrep(script_path, '"', '""'), strrep(root_dir, '"', '""'));
    [status, out] = system(cmd);
    if status ~= 0
        warning('Result folder view setup failed: %s', strtrim(out));
    elseif ~isempty(strtrim(out))
        fprintf('%s\n', strtrim(out));
    end
end

function tf = should_configure_views(cfg)
    tf = true;
    if ~isstruct(cfg) || ~isfield(cfg, 'gui') || ~isstruct(cfg.gui)
        return;
    end
    if isfield(cfg.gui, 'auto_configure_result_folders') && ~isempty(cfg.gui.auto_configure_result_folders)
        tf = logical(cfg.gui.auto_configure_result_folders);
    end
end
