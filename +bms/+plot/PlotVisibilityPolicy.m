classdef PlotVisibilityPolicy
    %PLOTVISIBILITYPOLICY Central visibility policy for analysis figures.
    %   Interactive MATLAB sessions retain the user's existing root figure
    %   default. Compiled runners and MATLAB -batch sessions create classic
    %   figures hidden. Saved FIG files are serialized with Visible='on'
    %   without ever showing the live analysis figure.

    methods (Static)
        function [guard, state] = enterForCurrentProcess()
            [background, reason] = bms.plot.PlotVisibilityPolicy.detectBackgroundProcess();
            if background
                [guard, state] = bms.plot.PlotVisibilityPolicy.enter('background');
            else
                [guard, state] = bms.plot.PlotVisibilityPolicy.enter('interactive');
            end
            state.reason = reason;
        end

        function [guard, state] = enter(mode)
            if nargin < 1 || isempty(mode)
                mode = 'auto';
            end
            mode = lower(char(string(mode)));
            if strcmp(mode, 'auto')
                [background, reason] = bms.plot.PlotVisibilityPolicy.detectBackgroundProcess();
                if background
                    mode = 'background';
                else
                    mode = 'interactive';
                end
            else
                reason = ['explicit_' mode];
            end
            if ~ismember(mode, {'background', 'interactive'})
                error('BMS:PlotVisibilityPolicy:InvalidMode', ...
                    'Unknown plot visibility mode: %s', mode);
            end

            original = char(string(get(groot, 'DefaultFigureVisible')));
            if strcmp(mode, 'background')
                set(groot, 'DefaultFigureVisible', 'off');
                guard = onCleanup(@() bms.plot.PlotVisibilityPolicy.restoreRootDefault(original));
            else
                % Interactive use must respect the user's current MATLAB
                % preference rather than forcing figures on or off.
                guard = onCleanup(@() []);
            end
            state = struct( ...
                'mode', mode, ...
                'reason', reason, ...
                'original_default', original, ...
                'effective_default', char(string(get(groot, 'DefaultFigureVisible'))));
        end

        function [background, reason] = detectBackgroundProcess()
            background = false;
            reason = 'interactive_matlab';
            try
                if isdeployed
                    background = true;
                    reason = 'compiled_runner';
                    return;
                end
            catch
                % isdeployed is available in supported MATLAB releases, but
                % keep source-mode diagnostics usable in restricted runtimes.
            end
            try
                if (exist('batchStartupOptionUsed', 'builtin') == 5 || ...
                        exist('batchStartupOptionUsed', 'file') == 2) && ...
                        batchStartupOptionUsed
                    background = true;
                    reason = 'matlab_batch';
                end
            catch
                % Older MATLAB releases without the startup probe remain
                % interactive unless they are deployed.
            end
        end

        function saveFigVisibleOn(fig, figPath)
            %SAVEFIGVISIBLEON Persist Visible='on' without an on-screen window.
            %   Modern FIG files contain both hgS_* and hgM_* payloads, and
            %   OPENFIG gives hgM_* precedence.  Rewriting hgS_* alone can
            %   therefore report Visible='on' while a normal OPENFIG still
            %   restores the hidden hgM_* figure.  Loading hgM_* in order to
            %   patch it materializes a duplicate graphics tree and is both
            %   expensive and unsafe for large figures.
            %
            %   When the live analysis figure is hidden, stage it far outside
            %   every practical desktop, serialize the complete figure with
            %   Visible='on', and immediately restore the live state.  SAVEFIG
            %   then writes matching hgS_* and hgM_* payloads, while the batch
            %   window never appears on screen.  OPENFIG moves the saved normal
            %   window back on screen for an interactive user.
            if ~isgraphics(fig, 'figure')
                error('BMS:PlotVisibilityPolicy:InvalidFigure', ...
                    'A valid classic MATLAB figure is required.');
            end
            figPath = char(string(figPath));
            restoreGuard = [];
            if strcmpi(char(string(fig.Visible)), 'off')
                state = bms.plot.PlotVisibilityPolicy.captureFigureState(fig);
                restoreGuard = onCleanup(@() ...
                    bms.plot.PlotVisibilityPolicy.restoreFigureState(fig, state));
                bms.plot.PlotVisibilityPolicy.stageOffscreenVisible(fig, state);
            end

            savefig(fig, figPath);
            clear restoreGuard;

            actual = bms.plot.PlotVisibilityPolicy.savedFigureVisibility(figPath);
            if ~strcmpi(actual, 'on')
                error('BMS:PlotVisibilityPolicy:SavedVisibilityMismatch', ...
                    'Saved FIG did not persist Visible=''on'': %s', figPath);
            end
        end

        function visibility = savedFigureVisibility(figPath)
            [payload, schemaName] = ...
                bms.plot.PlotVisibilityPolicy.serializedFigurePayload(figPath);
            graph = payload.(schemaName);
            if isfield(graph.properties, 'Visible')
                visibility = char(string(graph.properties.Visible));
            else
                % HG serialization omits properties that already have their
                % factory default. For a classic figure, an omitted Visible
                % property therefore means the saved figure opens 'on'.
                visibility = 'on';
            end
        end
    end

    methods (Static, Access = private)
        function state = captureFigureState(fig)
            state = struct( ...
                'visible', char(string(fig.Visible)), ...
                'units', char(string(fig.Units)), ...
                'position', double(fig.Position), ...
                'window_style', '', ...
                'window_state', '');
            if isprop(fig, 'WindowStyle')
                state.window_style = char(string(fig.WindowStyle));
            end
            if isprop(fig, 'WindowState')
                state.window_state = char(string(fig.WindowState));
            end
        end

        function stageOffscreenVisible(fig, state)
            % Normalize the window while it is still hidden so Position is
            % honored even if an interactive caller supplied a docked or
            % maximized figure.  The saved off-screen position is intentional:
            % OPENFIG calls MOVEGUI for a normal visible figure and brings it
            % onto the user's current desktop.
            if isprop(fig, 'WindowStyle') && ~strcmpi(state.window_style, 'normal')
                fig.WindowStyle = 'normal';
            end
            if isprop(fig, 'WindowState') && ~strcmpi(state.window_state, 'normal')
                fig.WindowState = 'normal';
            end
            fig.Units = 'pixels';
            sizePixels = double(fig.Position(3:4));
            sizePixels = max(sizePixels, [1 1]);
            fig.Position = [-100000 -100000 sizePixels];
            fig.Visible = 'on';
        end

        function restoreFigureState(fig, state)
            if ~isgraphics(fig, 'figure')
                return;
            end
            try
                % Hide first; every remaining restoration then happens with
                % no on-screen window even when SAVEFIG throws.
                fig.Visible = 'off';
                if isprop(fig, 'WindowStyle') && ~isempty(state.window_style)
                    fig.WindowStyle = state.window_style;
                end
                if isprop(fig, 'WindowState') && ~isempty(state.window_state)
                    fig.WindowState = state.window_state;
                end
                fig.Units = state.units;
                fig.Position = state.position;
                fig.Visible = state.visible;
            catch
                % Cleanup must not mask the original save error.  Make a final
                % best effort to keep a formerly hidden batch figure hidden.
                try
                    if strcmpi(state.visible, 'off')
                        fig.Visible = 'off';
                    end
                catch
                end
            end
        end

        function restoreRootDefault(value)
            try
                set(groot, 'DefaultFigureVisible', value);
            catch
                % Cleanup must not mask an analysis error during shutdown.
            end
        end

        function [payload, schemaName] = serializedFigurePayload(figPath)
            figPath = char(string(figPath));
            if ~isfile(figPath)
                error('BMS:PlotVisibilityPolicy:FigFileMissing', ...
                    'FIG file does not exist: %s', figPath);
            end
            % Do not call WHOS('-file', figPath) here. Modern FIG files also
            % contain an hgM_* object and WHOS materializes that object as a
            % hidden duplicate figure. WHO('-file', ...) only reads the MAT
            % directory and has no graphics side effect. Discover the hgS_*
            % name instead of assuming a small fixed set: MATLAB can emit
            % other schema suffixes for figures containing newer graphics
            % objects (for example ConstantLine or chart containers).
            variableNames = who('-file', figPath);
            candidates = variableNames(startsWith(variableNames, 'hgS_'));
            schemaName = '';
            graph = struct();
            metadataValue = [];
            hasMetadata = false;
            candidateDetails = strings(0, 1);
            for i = 1:numel(candidates)
                warningState = warning('off', 'MATLAB:load:variableNotFound');
                warningCleanup = onCleanup(@() warning(warningState));
                candidate = load(figPath, candidates{i}, 'meta_data', '-mat');
                clear warningCleanup;
                if ~isfield(candidate, candidates{i})
                    continue;
                end
                value = candidate.(candidates{i});
                if isstruct(value)
                    hasProperties = isscalar(value) && isfield(value, 'properties') && ...
                        isstruct(value.properties);
                    visibleField = hasProperties && isfield(value.properties, 'Visible');
                    candidateDetails(end + 1, 1) = sprintf( ...
                        '%s:%s:%s:properties=%d:Visible=%d', ...
                        candidates{i}, class(value), mat2str(size(value)), ...
                        hasProperties, visibleField); %#ok<AGROW>
                else
                    candidateDetails(end + 1, 1) = sprintf('%s:%s:%s', ...
                        candidates{i}, class(value), mat2str(size(value))); %#ok<AGROW>
                end
                if isstruct(value) && isscalar(value) && ...
                        isfield(value, 'properties') && ...
                        isstruct(value.properties)
                    schemaName = candidates{i};
                    graph = value;
                    if isfield(candidate, 'meta_data')
                        metadataValue = candidate.meta_data;
                        hasMetadata = true;
                    end
                    break;
                end
            end
            if isempty(schemaName)
                error('BMS:PlotVisibilityPolicy:SerializableFigureMissing', ...
                    ['FIG file has no writable hgS_* figure payload ' ...
                     '(variables: %s; candidates: %s): %s'], ...
                    strjoin(variableNames, ', '), strjoin(candidateDetails, ', '), figPath);
            end

            payload = struct();
            payload.(schemaName) = graph;
            if hasMetadata
                payload.meta_data = metadataValue;
            end
        end
    end
end
