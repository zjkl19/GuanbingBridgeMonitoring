classdef ArtifactCollector
    %ARTIFACTCOLLECTOR Collects module stats and figure artifacts for manifests.

    methods (Static)
        function artifacts = collectModule(root, key, statsPath, startedAt, cfg)
            if nargin < 5, cfg = struct(); end
            artifacts = {};
            if nargin >= 3 && ~isempty(statsPath) && isfile(statsPath)
                artifacts{end+1} = bms.data.ArtifactCollector.record('stats', statsPath, 'stats'); %#ok<AGROW>
            end
            dirs = bms.data.ArtifactCollector.moduleOutputDirs(root, key, cfg);
            cutoff = [];
            if nargin >= 4 && ~isempty(startedAt) && isdatetime(startedAt) && ~isnat(startedAt)
                cutoff = startedAt - minutes(2);
            end
            for i = 1:numel(dirs)
                files = bms.data.ArtifactCollector.listImageFiles(dirs{i}, cutoff);
                for j = 1:numel(files)
                    role = bms.data.ArtifactCollector.inferRole(files{j}, key);
                    kind = 'figure';
                    if endsWith(lower(files{j}), '.plot.json')
                        kind = 'plot_provenance';
                        role = 'plot_provenance';
                    end
                    artifacts{end+1} = bms.data.ArtifactCollector.record(kind, files{j}, role); %#ok<AGROW>
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
            patterns = {'*.jpg','*.jpeg','*.png','*.emf','*.fig','*.plot.json'};
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

        function rec = record(kind, path, role)
            if nargin < 3 || isempty(role)
                role = bms.data.ArtifactCollector.inferRole(path, '');
            end
            rec = struct();
            rec.kind = char(kind);
            rec.role = char(role);
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

        function role = inferRole(path, moduleKey)
            text = lower(char(string(path)));
            moduleKey = char(string(moduleKey));
            role = 'time_history';
            if endsWith(text, '.xlsx') || strcmpi(moduleKey, 'stats')
                role = 'stats';
            elseif contains(text, 'rms10') || contains(text, 'rms_10')
                role = 'rms10min';
            elseif contains(text, 'specfreq') || contains(text, 'spectrum') || contains(text, 'psd') || contains(text, char([39057 35889]))
                role = 'spectrum';
            elseif contains(text, 'boxplot') || contains(text, char([31665 32447]))
                role = 'boxplot';
            elseif contains(text, 'windrose') || contains(text, char([39118 29611 29808]))
                role = 'wind_rose';
            elseif contains(text, 'freq') || contains(text, char([39057 29575]))
                role = 'frequency_distribution';
            elseif contains(text, 'speed10min') || contains(text, '10min')
                role = 'wind_speed10min';
            elseif contains(text, 'filt') || contains(text, char([28388 27874]))
                role = 'filtered';
            elseif contains(text, 'orig') || contains(text, char([21407 22987]))
                role = 'raw';
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
                    spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('deflection');
                    names = { ...
                        bms.analyzer.StructuralFilteredSeriesPipeline.deflectionSingleOutputDir(struct(), spec, 'raw'), ...
                        bms.analyzer.StructuralFilteredSeriesPipeline.deflectionSingleOutputDir(struct(), spec, 'filtered'), ...
                        bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupOutputDir(struct(), spec, 'raw'), ...
                        bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupOutputDir(struct(), spec, 'filtered')};
                case 'bearing_displacement'
                    spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('bearing_displacement');
                    names = { ...
                        bms.analyzer.StructuralFilteredSeriesPipeline.bearingSingleOutputDir(struct(), spec, 'raw'), ...
                        bms.analyzer.StructuralFilteredSeriesPipeline.bearingSingleOutputDir(struct(), spec, 'filtered'), ...
                        bms.analyzer.StructuralFilteredSeriesPipeline.bearingGroupOutputDir(struct(), spec, 'raw'), ...
                        bms.analyzer.StructuralFilteredSeriesPipeline.bearingGroupOutputDir(struct(), spec, 'filtered')};
                case 'tilt'
                    names = {'时程曲线_倾斜'};
                case 'acceleration'
                    names = {'时程曲线_加速度','时程曲线_加速度_组图','时程曲线_加速度_RMS10min','时程曲线_加速度_RMS10min_组图'};
                case 'cable_accel'
                    names = {'时程曲线_索力加速度','时程曲线_索力加速度_组图','时程曲线_索力加速度_RMS10min','时程曲线_索力加速度_RMS10min_组图'};
                case 'accel_spectrum'
                    names = {'频谱峰值曲线_加速度','频谱峰值曲线_加速度_组图','PSD_备查'};
                case 'cable_accel_spectrum'
                    names = {'频谱峰值曲线_索力加速度','索力时程图','索力时程图_组图','PSD_备查_索力加速度'};
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
            if strcmp(styleKey, 'dynamic_strain_highpass'), styleKey = 'dynamic_strain'; end
            if strcmp(styleKey, 'dynamic_strain_lowpass'), styleKey = 'dynamic_strain_lowpass'; end
            if ~isfield(cfg.plot_styles, styleKey) || ~isstruct(cfg.plot_styles.(styleKey))
                return;
            end
            style = cfg.plot_styles.(styleKey);
            if strcmp(char(key), 'deflection')
                spec = bms.analyzer.StructuralFilteredSeriesPipeline.spec('deflection');
                names = { ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.deflectionSingleOutputDir(style, spec, 'raw'), ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.deflectionSingleOutputDir(style, spec, 'filtered'), ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupOutputDir(style, spec, 'raw'), ...
                    bms.analyzer.StructuralFilteredSeriesPipeline.deflectionGroupOutputDir(style, spec, 'filtered')};
                return;
            end
            fields = {'output_dir','single_output_dir','group_output_dir','rms_group_output_dir','boxplot_output_dir', ...
                'output_dir_ts','group_output_dir_ts','output_dir_crack','output_dir_temp', ...
                'raw_output_dir','filtered_output_dir','raw_group_output_dir','filtered_group_output_dir', ...
                'freq_group_output_dir','force_output_dir','force_group_output_dir'};
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
