function save_config(cfg, filepath, make_backup)
% save_config  Save configuration struct to JSON with optional backup.
%   save_config(cfg, filepath, make_backup)
%   - cfg        : struct to encode
%   - filepath   : target JSON path
%   - make_backup: true to create a timestamped backup of the existing file
%
% Behavior:
%   * Ensures target folder exists.
%   * Optionally writes a backup <name>_backup_yyyymmdd_HHMMSS.json if the
%     target file already exists and make_backup is true.
%   * Uses jsonencode with PrettyPrint for readability.

    if nargin < 3, make_backup = true; end
    if nargin < 2 || isempty(filepath)
        error('filepath is required');
    end
    outDir = fileparts(filepath);
    if ~isempty(outDir) && ~exist(outDir,'dir')
        mkdir(outDir);
    end

    if make_backup && isfile(filepath)
        [p,n,~] = fileparts(filepath);
        ts = datestr(now,'yyyymmdd_HHMMSS');
        backup = fullfile(p, sprintf('%s_backup_%s.json', n, ts));
        copyfile(filepath, backup);
    end

    % 在写入前，将 per_point 的测点字段名由下划线改为连字符，便于 JSON 中直观显示
    cfg_out = hyphenize_point_ids(cfg);

    % jsonencode 不接受 options 结构体，必须以 Name-Value 传参
    % 否则会报 “名称参数类型必须为字符串标量或字符向量”
    txt = jsonencode(cfg_out, 'PrettyPrint', true, 'ConvertInfAndNaN', true);
    fid = fopen(filepath,'wt');
    if fid < 0
        error('无法写入配置文件: %s', filepath);
    end
    fwrite(fid, txt, 'char');
    fclose(fid);
end

function cfg2 = hyphenize_point_ids(cfg1)
% 将 per_point 下的测点字段名中的下划线改为连字符，仅影响输出到 JSON，
% 内部使用仍保留 cfg1 原始形式。
    cfg2 = cfg1;
    if ~isfield(cfg1,'per_point') || ~isstruct(cfg1.per_point), return; end
    sensors = fieldnames(cfg1.per_point);
    for i = 1:numel(sensors)
        s = sensors{i};
        pts = cfg1.per_point.(s);
        if ~isstruct(pts), continue; end
        newPts = struct();
        fn = fieldnames(pts);
        for k = 1:numel(fn)
            pid = fn{k};
            pid_hy = strrep(pid,'_','-');
            newPts.(pid_hy) = pts.(pid);
        end
        cfg2.per_point.(s) = newPts;
    end
end
