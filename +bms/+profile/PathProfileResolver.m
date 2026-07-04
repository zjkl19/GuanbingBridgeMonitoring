classdef PathProfileResolver
    %PATHPROFILERESOLVER Applies machine-specific path overrides.
    %
    % Bridge profiles keep business defaults. This resolver applies the
    % current machine's storage layout from config/path_profiles*.json.

    methods (Static)
        function profile = active(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            profile = bms.profile.PathProfileResolver.emptyProfile();
            entries = bms.profile.PathProfileResolver.loadProfiles(projectRoot);
            if isempty(entries)
                return;
            end

            requested = strtrim(char(string(getenv('GUANBING_PATH_PROFILE'))));
            if ~isempty(requested)
                idx = bms.profile.PathProfileResolver.findProfileById(entries, requested);
                if idx > 0
                    profile = bms.profile.PathProfileResolver.markProfile( ...
                        entries(idx), 'env', sprintf('GUANBING_PATH_PROFILE=%s', requested));
                else
                    profile.match_type = 'env_missing';
                    profile.match_reason = sprintf('GUANBING_PATH_PROFILE=%s not found', requested);
                end
                return;
            end

            host = lower(strtrim(char(string(getenv('COMPUTERNAME')))));
            if ~isempty(host)
                for i = numel(entries):-1:1
                    if bms.profile.PathProfileResolver.profileMatchesHost(entries(i), host)
                        profile = bms.profile.PathProfileResolver.markProfile( ...
                            entries(i), 'host', sprintf('COMPUTERNAME=%s', host));
                        return;
                    end
                end
            end

            idx = bms.profile.PathProfileResolver.findProfileByExistingPaths(entries, projectRoot);
            if idx > 0
                [~, evidence] = bms.profile.PathProfileResolver.profilePathScore(entries(idx), projectRoot);
                profile = bms.profile.PathProfileResolver.markProfile( ...
                    entries(idx), 'path_exists', evidence);
            end
        end

        function [idx, evidence] = detectProfileByExistingPaths(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            entries = bms.profile.PathProfileResolver.loadProfiles(projectRoot);
            idx = bms.profile.PathProfileResolver.findProfileByExistingPaths(entries, projectRoot);
            evidence = '';
            if idx > 0
                [~, evidence] = bms.profile.PathProfileResolver.profilePathScore(entries(idx), projectRoot);
            end
        end

        function info = describeActive(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            profile = bms.profile.PathProfileResolver.active(projectRoot);
            info = struct();
            info.profile_id = '';
            info.match_type = 'none';
            info.match_reason = '';
            info.source_path = '';
            if isstruct(profile)
                names = intersect(fieldnames(info), fieldnames(profile), 'stable');
                for i = 1:numel(names)
                    info.(names{i}) = profile.(names{i});
                end
            end
        end

        function path = resolveLogRoot(dataRoot, defaultLogRoot, projectRoot)
            if nargin < 3 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            if nargin < 2 || isempty(defaultLogRoot)
                defaultLogRoot = fullfile(char(dataRoot), 'run_logs');
            end
            path = bms.profile.BridgeProfile.normalizePathText(defaultLogRoot);
            profile = bms.profile.PathProfileResolver.active(projectRoot);
            if isstruct(profile) && isfield(profile, 'path_replacements')
                path = bms.profile.PathProfileResolver.applyReplacements(path, profile.path_replacements, projectRoot);
            end
        end

        function profile = markProfile(profile, matchType, reason)
            profile.match_type = char(string(matchType));
            profile.match_reason = char(string(reason));
        end

        function idx = findProfileByExistingPaths(entries, projectRoot)
            idx = 0;
            bestScore = 0;
            for i = numel(entries):-1:1
                [score, ~] = bms.profile.PathProfileResolver.profilePathScore(entries(i), projectRoot);
                if score > bestScore
                    bestScore = score;
                    idx = i;
                end
            end
            if bestScore <= 0
                idx = 0;
            end
        end

        function [score, evidence] = profilePathScore(profile, projectRoot)
            score = 0;
            evidenceParts = {};

            if isfield(profile, 'data_roots') && isstruct(profile.data_roots)
                fields = fieldnames(profile.data_roots);
                for i = 1:numel(fields)
                    raw = bms.profile.PathProfileResolver.structText(profile.data_roots, fields{i}, '');
                    [delta, hit] = bms.profile.PathProfileResolver.pathExistScore(raw, projectRoot, 4, 1);
                    score = score + delta;
                    if ~isempty(hit)
                        evidenceParts{end+1} = hit; %#ok<AGROW>
                    end
                end
            end

            if isfield(profile, 'path_replacements') && ~isempty(profile.path_replacements)
                rows = bms.profile.PathProfileResolver.rowsFromValue(profile.path_replacements);
                for i = 1:numel(rows)
                    row = rows{i};
                    if ~isstruct(row) || ~isfield(row, 'to')
                        continue;
                    end
                    [delta, hit] = bms.profile.PathProfileResolver.pathExistScore(row.to, projectRoot, 3, 1);
                    score = score + delta;
                    if ~isempty(hit)
                        evidenceParts{end+1} = hit; %#ok<AGROW>
                    end
                end
            end

            if isempty(evidenceParts)
                evidence = '';
            else
                evidence = strjoin(evidenceParts(1:min(3, numel(evidenceParts))), '; ');
            end
        end

        function [score, evidence] = pathExistScore(rawPath, projectRoot, exactScore, parentScore)
            score = 0;
            evidence = '';
            path = bms.profile.PathProfileResolver.resolvePathTokens(rawPath, projectRoot);
            if isempty(path)
                return;
            end
            if exist(path, 'dir') == 7
                score = exactScore;
                evidence = path;
                return;
            end
            parent = bms.profile.PathProfileResolver.parentPath(path);
            if ~isempty(parent) && exist(parent, 'dir') == 7
                score = parentScore;
                evidence = parent;
            end
        end

        function parent = parentPath(path)
            parent = '';
            path = bms.profile.BridgeProfile.normalizePathText(path);
            if isempty(path)
                return;
            end
            while endsWith(path, filesep) || endsWith(path, '/') || endsWith(path, '\')
                if numel(path) <= 3
                    return;
                end
                path = path(1:end-1);
            end
            parent = fileparts(path);
            if isempty(parent) || strcmpi(parent, path) || numel(parent) <= 3
                parent = '';
            end
        end

        function rows = rowsFromValue(value)
            if isempty(value)
                rows = {};
            elseif iscell(value)
                rows = value;
            else
                rows = num2cell(value);
            end
        end

        function root = resolveDataRoot(bridgeId, defaultRoot, projectRoot)
            if nargin < 3 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            root = bms.profile.BridgeProfile.normalizePathText(defaultRoot);
            profile = bms.profile.PathProfileResolver.active(projectRoot);
            if ~isstruct(profile) || ~isfield(profile, 'profile_id') || isempty(profile.profile_id)
                return;
            end

            key = matlab.lang.makeValidName(lower(char(string(bridgeId))));
            if isfield(profile, 'data_roots') && isstruct(profile.data_roots) && isfield(profile.data_roots, key)
                candidate = bms.profile.PathProfileResolver.structText(profile.data_roots, key, '');
                if ~isempty(candidate)
                    root = bms.profile.PathProfileResolver.resolvePathTokens(candidate, projectRoot);
                    return;
                end
            end

            if isfield(profile, 'path_replacements')
                root = bms.profile.PathProfileResolver.applyReplacements(root, profile.path_replacements, projectRoot);
            end
        end

        function entries = loadProfiles(projectRoot)
            if nargin < 1 || isempty(projectRoot)
                projectRoot = bms.core.PathResolver.projectRoot();
            end
            entries = struct([]);
            files = { ...
                fullfile(projectRoot, 'config', 'path_profiles.json'), ...
                fullfile(projectRoot, 'config', 'path_profiles.local.json')};
            for i = 1:numel(files)
                more = bms.profile.PathProfileResolver.loadFile(files{i});
                if isempty(more)
                    continue;
                end
                if isempty(entries)
                    entries = more;
                else
                    entries = [entries(:); more(:)]; %#ok<AGROW>
                end
            end
        end
    end

    methods (Static, Access = private)
        function profile = emptyProfile()
            profile = struct('profile_id', '', 'hostnames', {{}}, ...
                'data_roots', struct(), 'path_replacements', [], 'source_path', '', ...
                'match_type', 'none', 'match_reason', '');
        end

        function profiles = loadFile(path)
            profiles = struct([]);
            if exist(path, 'file') ~= 2
                return;
            end
            try
                data = jsondecode(fileread(path));
                if ~isfield(data, 'profiles')
                    return;
                end
                rows = data.profiles;
                for i = 1:numel(rows)
                    if iscell(rows)
                        row = rows{i};
                    else
                        row = rows(i);
                    end
                    row.source_path = path;
                    profiles = bms.profile.PathProfileResolver.appendProfile(profiles, row); %#ok<AGROW>
                end
            catch ME
                warning('BMS:PathProfile:LoadFailed', 'Failed to load path profile %s: %s', path, ME.message);
                profiles = struct([]);
            end
        end

        function profiles = appendProfile(profiles, row)
            base = bms.profile.PathProfileResolver.emptyProfile();
            names = intersect(fieldnames(row), fieldnames(base), 'stable');
            for i = 1:numel(names)
                base.(names{i}) = row.(names{i});
            end
            if isempty(profiles)
                profiles = base;
            else
                profiles(end+1, 1) = base;
            end
        end

        function idx = findProfileById(entries, profileId)
            idx = 0;
            wanted = lower(strtrim(char(string(profileId))));
            for i = numel(entries):-1:1
                current = '';
                if isfield(entries(i), 'profile_id') && ~isempty(entries(i).profile_id)
                    current = lower(strtrim(char(string(entries(i).profile_id))));
                end
                if strcmp(current, wanted)
                    idx = i;
                    return;
                end
            end
        end

        function tf = profileMatchesHost(profile, host)
            tf = false;
            if ~isfield(profile, 'hostnames') || isempty(profile.hostnames)
                return;
            end
            hosts = profile.hostnames;
            if ischar(hosts) || isstring(hosts)
                hosts = cellstr(string(hosts));
            elseif ~iscell(hosts)
                hosts = cellstr(string(hosts(:)));
            end
            for i = 1:numel(hosts)
                pat = lower(strtrim(char(string(hosts{i}))));
                if isempty(pat)
                    continue;
                end
                if strcmp(pat, host) || strcmp(pat, '*')
                    tf = true;
                    return;
                end
            end
        end

        function value = structText(s, fieldName, fallback)
            value = fallback;
            if isstruct(s) && isfield(s, fieldName) && ~isempty(s.(fieldName))
                value = char(string(s.(fieldName)));
            end
        end

        function path = resolvePathTokens(path, projectRoot)
            path = bms.profile.BridgeProfile.normalizePathText(path);
            path = strrep(path, '<project_root>', projectRoot);
            path = strrep(path, '<COMPUTERNAME>', char(string(getenv('COMPUTERNAME'))));
        end

        function root = applyReplacements(root, replacements, projectRoot)
            if isempty(root) || isempty(replacements)
                return;
            end
            rows = bms.profile.PathProfileResolver.rowsFromValue(replacements);
            for i = 1:numel(rows)
                row = rows{i};
                if ~isstruct(row) || ~isfield(row, 'from') || ~isfield(row, 'to')
                    continue;
                end
                from = bms.profile.PathProfileResolver.resolvePathTokens(row.from, projectRoot);
                to = bms.profile.PathProfileResolver.resolvePathTokens(row.to, projectRoot);
                if isempty(from)
                    continue;
                end
                if bms.profile.PathProfileResolver.isPathPrefix(root, from)
                    root = [to root(numel(from)+1:end)];
                    root = bms.profile.BridgeProfile.normalizePathText(root);
                    return;
                end
            end
        end

        function tf = isPathPrefix(pathValue, prefixValue)
            pathValue = bms.profile.BridgeProfile.normalizePathText(pathValue);
            prefixValue = bms.profile.BridgeProfile.normalizePathText(prefixValue);
            pathLower = lower(pathValue);
            prefixLower = lower(prefixValue);
            tf = false;
            if ~startsWith(pathLower, prefixLower)
                return;
            end
            if numel(pathLower) == numel(prefixLower)
                tf = true;
                return;
            end
            nextChar = pathLower(numel(prefixLower) + 1);
            tf = any(nextChar == ['/' '\']);
        end
    end
end
