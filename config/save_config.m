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

    % 提取并移除名称映射（安全字段名 -> 原始显示名），用于输出时还原
    name_map = struct();
    if isfield(cfg,'name_map_global')
        name_map = cfg.name_map_global;
        cfg = rmfield(cfg,'name_map_global');
    end

    % jsonencode 不接受 options 结构体，必须以 Name-Value 传参
    % 否则会报 “名称参数类型必须为字符串标量或字符向量”
    txt = jsonencode(cfg, 'PrettyPrint', true, 'ConvertInfAndNaN', true);

    % 用名称映射恢复原始键名（含连字符或下划线混用）
    if ~isempty(fieldnames(name_map))
        keys = fieldnames(name_map);
        % 为避免部分匹配，按键长度降序替换
        [~,idx] = sort(cellfun(@numel, keys),'descend');
        keys = keys(idx);
        for i = 1:numel(keys)
            safe = keys{i};
            orig = name_map.(safe);
            txt = regexprep(txt, ['"' , regexptranslate('escape', safe) , '"'], ['"' orig '"']);
        end
    end
    fid = fopen(filepath,'wt');
    if fid < 0
        error('无法写入配置文件: %s', filepath);
    end
    fwrite(fid, txt, 'char');
    fclose(fid);
end
