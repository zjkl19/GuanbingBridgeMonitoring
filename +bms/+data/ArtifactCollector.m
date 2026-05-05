classdef ArtifactCollector
    %ARTIFACTCOLLECTOR Collects module stats and figure artifacts for manifests.

    methods (Static)
        function artifacts = collectModule(root, key, statsPath, startedAt, cfg)
            if nargin < 5, cfg = struct(); end
            artifacts = {};
            if nargin >= 3 && ~isempty(statsPath) && isfile(statsPath)
                artifacts{end+1} = bms.data.ArtifactCollector.record('stats', statsPath); %#ok<AGROW>
            end
            dirs = bms.data.ArtifactCollector.moduleOutputDirs(root, key, cfg);
            cutoff = [];
            if nargin >= 4 && ~isempty(startedAt) && isdatetime(startedAt) && ~isnat(startedAt)
                cutoff = startedAt - minutes(2);
            end
            for i = 1:numel(dirs)
                files = bms.data.ArtifactCollector.listImageFiles(dirs{i}, cutoff);
                for j = 1:numel(files)
                    artifacts{end+1} = bms.data.ArtifactCollector.record('figure', files{j}); %#ok<AGROW>
                end
            end
        end

        function dirs = moduleOutputDirs(root, key, cfg)
            root = char(root);
            names = bms.data.ArtifactCollector.defaultOutputDirNames(key);
            names = [names, bms.data.ArtifactCollector.configOutputDirNames(key, cfg)]; %#ok<AGROW>
            dirs = {};
            seen = {};
            for i = 1:numel(names)
                name = char(string(names{i}));
                if isempty(name), continue; end
                if bms.data.ArtifactCollector.isAbsolutePath(name)
                    p = name;
                else
                    p = fullfile(root, name);
                end
                if exist(p, 'dir') && ~ismember(p, seen)
                    dirs{end+1} = p; %#ok<AGROW>
                    seen{end+1} = p; %#ok<AGROW>
                end
            end
        end

        function files = listImageFiles(folder, cutoff)
            files = {};
            if nargin < 2, cutoff = []; end
            if ~exist(folder, 'dir'), return; end
            folders = {folder};
            subdirs = dir(folder);
            subdirs = subdirs([subdirs.isdir]);
            for k = 1:numel(subdirs)
                if any(strcmp(subdirs(k).name, {'.','..'})), continue; end
                folders{end+1} = fullfile(subdirs(k).folder, subdirs(k).name); %#ok<AGROW>
            end
            patterns = {'*.jpg','*.jpeg','*.png','*.emf','*.fig'};
            for f = 1:numel(folders)
                for i = 1:numel(patterns)
                    d = dir(fullfile(folders{f}, patterns{i}));
                    d = d(~[d.isdir]);
                    for j = 1:numel(d)
                        if ~isempty(cutoff)
                            mt = datetime(d(j).datenum, 'ConvertFrom', 'datenum');
                            if mt < cutoff
                                continue;
                            end
                        end
                        files{end+1} = fullfile(d(j).folder, d(j).name); %#ok<AGROW>
                    end
                end
            end
        end

        function rec = record(kind, path)
            rec = struct();
            rec.kind = char(kind);
            rec.path = char(path);
            rec.exists = isfile(path);
            rec.bytes = 0;
            rec.modified_at = '';
            if rec.exists
                d = dir(path);
                if ~isempty(d)
                    rec.bytes = d.bytes;
                    rec.modified_at = datestr(d.datenum, 'yyyy-mm-dd HH:MM:ss');
                end
            end
        end

        function names = defaultOutputDirNames(key)
            switch char(key)
                case 'temperature'
                    names = {'时程曲线_温度'};
                case 'humidity'
                    names = {'时程曲线_湿度','频率分布_湿度'};
                case 'rainfall'
                    names = {'时程曲线_雨量'};
                case 'gnss'
                    names = {'时程曲线_GNSS'};
                case 'deflection'
                    names = {'时程曲线_挠度','时程曲线_挠度_滤波'};
                case 'bearing_displacement'
                    names = {'时程曲线_支座位移'};
                case 'tilt'
                    names = {'时程曲线_倾斜'};
                case 'acceleration'
                    names = {'时程曲线_加速度','时程曲线_加速度_RMS10min'};
                case 'cable_accel'
                    names = {'时程曲线_索力加速度','时程曲线_索力加速度_RMS10min'};
                case 'accel_spectrum'
                    names = {'频谱峰值曲线_加速度','PSD_备查'};
                case 'cable_accel_spectrum'
                    names = {'频谱峰值曲线_索力加速度','索力时程曲线','PSD_备查_索力加速度'};
                case 'crack'
                    names = {'时程曲线_裂缝宽度','时程曲线_裂缝温度'};
                case 'strain'
                    names = {'时程曲线_应变','时程曲线_应变_组图','箱线图_应变'};
                case 'dynamic_strain_highpass'
                    names = {'时程曲线_动应变_高通滤波','箱线图_动应变_高通滤波','动应变箱线图_高通滤波'};
                case 'dynamic_strain_lowpass'
                    names = {'时程曲线_动应变_低通滤波','箱线图_动应变_低通滤波','动应变箱线图_低通滤波'};
                case 'wind'
                    names = {'风速风向结果','风速时程','风向时程','10min平均风速','风玫瑰'};
                case {'earthquake','eq'}
                    names = {'地震动结果','时程曲线_地震动'};
                case 'wim'
                    names = {'WIM/results','WIM_results','wim_results'};
                otherwise
                    names = {};
            end
        end

        function names = configOutputDirNames(key, cfg)
            names = {};
            if ~isstruct(cfg) || ~isfield(cfg, 'plot_styles') || ~isstruct(cfg.plot_styles)
                return;
            end
            styleKey = char(key);
            if strcmp(styleKey, 'earthquake'), styleKey = 'eq'; end
            if ~isfield(cfg.plot_styles, styleKey) || ~isstruct(cfg.plot_styles.(styleKey))
                return;
            end
            style = cfg.plot_styles.(styleKey);
            fields = {'output_dir','group_output_dir','boxplot_output_dir','output_dir_crack','output_dir_temp'};
            for i = 1:numel(fields)
                if isfield(style, fields{i}) && ~isempty(style.(fields{i}))
                    names{end+1} = style.(fields{i}); %#ok<AGROW>
                end
            end
            if isfield(style, 'output') && isstruct(style.output) && isfield(style.output, 'root_dir')
                names{end+1} = style.output.root_dir; %#ok<AGROW>
            end
        end

        function tf = isAbsolutePath(p)
            p = char(p);
            tf = startsWith(p, filesep) || ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')) || startsWith(p, '\\');
        end
    end
end
