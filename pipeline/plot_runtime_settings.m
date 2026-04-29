function settings = plot_runtime_settings(action, values)
% plot_runtime_settings Store lightweight runtime plot-save settings.
%   S = plot_runtime_settings() returns current settings.
%   S = plot_runtime_settings('get') returns current settings.
%   plot_runtime_settings('set', VALUES) updates current settings.
%   plot_runtime_settings('reset') resets to defaults.

    persistent runtimeSettings

    if isempty(runtimeSettings)
        runtimeSettings = default_settings();
    end

    if nargin < 1 || isempty(action)
        action = 'get';
    end

    switch lower(char(string(action)))
        case 'get'
            % no-op
        case 'set'
            if nargin < 2 || ~isstruct(values)
                values = struct();
            end
            runtimeSettings = merge_settings(runtimeSettings, values);
        case 'reset'
            runtimeSettings = default_settings();
        otherwise
            error('plot_runtime_settings:InvalidAction', 'Unsupported action: %s', char(string(action)));
    end

    settings = runtimeSettings;
end

function settings = default_settings()
    settings = struct( ...
        'save_fig', true, ...
        'lightweight_fig', true, ...
        'fig_max_points', 50000, ...
        'append_timestamp', false, ...
        'gap_mode', 'break', ...
        'gap_break_factor', 5);
end

function merged = merge_settings(base, values)
    merged = base;
    fields = fieldnames(values);
    for i = 1:numel(fields)
        name = fields{i};
        merged.(name) = values.(name);
    end
    if ~isfield(merged, 'save_fig') || isempty(merged.save_fig)
        merged.save_fig = true;
    else
        merged.save_fig = logical(merged.save_fig);
    end
    if ~isfield(merged, 'lightweight_fig') || isempty(merged.lightweight_fig)
        merged.lightweight_fig = true;
    else
        merged.lightweight_fig = logical(merged.lightweight_fig);
    end
    if ~isfield(merged, 'fig_max_points') || isempty(merged.fig_max_points) || ...
            ~isfinite(merged.fig_max_points) || merged.fig_max_points < 1000
        merged.fig_max_points = 50000;
    else
        merged.fig_max_points = round(merged.fig_max_points);
    end
    if ~isfield(merged, 'append_timestamp') || isempty(merged.append_timestamp)
        merged.append_timestamp = false;
    else
        merged.append_timestamp = logical(merged.append_timestamp);
    end
    if ~isfield(merged, 'gap_mode') || isempty(merged.gap_mode)
        merged.gap_mode = 'break';
    else
        merged.gap_mode = lower(char(string(merged.gap_mode)));
        if ~ismember(merged.gap_mode, {'break','connect'})
            merged.gap_mode = 'break';
        end
    end
    if ~isfield(merged, 'gap_break_factor') || isempty(merged.gap_break_factor) || ...
            ~isfinite(merged.gap_break_factor) || merged.gap_break_factor <= 1
        merged.gap_break_factor = 5;
    else
        merged.gap_break_factor = double(merged.gap_break_factor);
    end
end

