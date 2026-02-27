function play_notify_sound(kind, cfg)
% play_notify_sound Play short beep patterns for task status.
%   play_notify_sound()             -> success
%   play_notify_sound('success')    -> success
%   play_notify_sound('error')      -> error
%   play_notify_sound('task_done')  -> task done
%
% cfg.notify.mode supports: 'beep' (default)

    if nargin < 1 || isempty(kind)
        kind = 'success';
    end
    if nargin < 2
        cfg = struct();
    end

    mode = 'beep';
    if isstruct(cfg) && isfield(cfg, 'notify') && isstruct(cfg.notify) ...
            && isfield(cfg.notify, 'mode') && ~isempty(cfg.notify.mode)
        mode = lower(string(cfg.notify.mode));
    end

    if mode ~= "beep"
        return;
    end

    switch lower(string(kind))
        case "error"
            do_beep_pattern([0.06 0.06 0.06], [0.10 0.10]);
        case "task_done"
            do_beep_pattern([0.08 0.08], [0.08]);
        otherwise
            do_beep_pattern(0.12, []);
    end
end

function do_beep_pattern(on_secs, off_secs)
    if ~isvector(on_secs), on_secs = on_secs(:)'; end
    if isempty(off_secs), off_secs = zeros(1, max(numel(on_secs)-1,0)); end
    if numel(off_secs) < numel(on_secs)-1
        off_secs = [off_secs, repmat(off_secs(end), 1, numel(on_secs)-1-numel(off_secs))];
    end
    for i = 1:numel(on_secs)
        beep;
        pause(on_secs(i));
        if i <= numel(off_secs)
            pause(off_secs(i));
        end
    end
end
