function extract_model_params(models)
%EXTRACT_MODEL_PARAMS Extract Simulink model parameters (power-simulink-rule companion tool)
%   Usage:
%     extract_model_params('my_model')                   % by model name (must be on path)
%     extract_model_params('D:\path\model.slx')          % by full path
%     extract_model_params({'m1','m2'})                  % multiple models
%
%   Extracts: solver settings / powergui mask parameters / top-level block list
%   with mask values / PID parameters / SampleTime distribution. Prints to the
%   command window.
%
%   Notes:
%   - Model names starting with a digit/parenthesis/hyphen cannot be load_system-ed
%     directly; the script automatically copyfile's to a temp dir and renames
%     before loading (original file untouched)
%   - Read-only models are only read, never saved
%   - In R2024b the DiscreteIntegrator gain parameter is 'gainval' (older
%     releases used 'GainValue')

if nargin < 1
    models = {'my_model'};
end
if ischar(models) || isstring(models)
    models = cellstr(models);
end

for k = 1:numel(models)
    p = models{k};
    mdl = load_model_safe(p);
    if isempty(mdl), continue; end
    analyze_model(mdl);
    close_system(mdl, 0);
end
end

%% Load model (handles illegal model names)
function mdl = load_model_safe(p)
mdl = '';
if exist(p, 'file')
    % Full path: check model name legality
    [~, name] = fileparts(p);
    if isvarname(name) && ~strcmp(name(1), '_')
        try
            load_system(p);
            mdl = name;
            return;
        catch
        end
    end
    % Illegal name -> copy and rename
    td = tempname; mkdir(td);
    newname = ['m' num2str(round(rand*1e6))];
    newf = fullfile(td, [newname '.slx']);
    try
        copyfile(p, newf);
        load_system(newf);
        mdl = newname;
        fprintf('### Illegal model name, loaded as copy %s (original untouched)\n', newf);
    catch e
        fprintf('### Load failed %s: %s\n', p, e.message);
    end
else
    try
        load_system(p);
        mdl = p;
    catch e
        fprintf('### Load failed %s: %s\n', p, e.message);
    end
end
end

%% Analyze a single model
function analyze_model(mdl)
fprintf('\n=== MODEL: %s ===\n', mdl);
% Solver
fprintf('Solver=%s | SolverType=%s | FixedStep=%s | StopTime=%s | MaxStep=%s | StartTime=%s\n', ...
    get_param(mdl,'Solver'), get_param(mdl,'SolverType'), get_param(mdl,'FixedStep'), ...
    get_param(mdl,'StopTime'), get_param(mdl,'MaxStep'), get_param(mdl,'StartTime'));
% powergui
try
    pg = [mdl '/powergui'];
    mv = get_param(pg,'MaskValues'); mn = get_param(pg,'MaskNames');
    s = 'powergui: ';
    for i = 1:min(numel(mn),8), s = [s sprintf('%s=%s | ', mn{i}, mv{i})]; end
    fprintf('%s\n', s);
catch
end
% Top-level blocks
blks = find_system(mdl,'SearchDepth',1,'LookUnderMasks','all');
fprintf('TopLevel blocks=%d\n', numel(blks)-1);
for i = 2:numel(blks)
    b = blks{i}; bt = get_param(b,'BlockType');
    nm = b(length(mdl)+2:end);
    mt = ''; try, mt = get_param(b,'MaskType'); catch, end
    if ~isempty(mt)
        if strcmp(mt,'PSB option menu block') || strcmp(mt,'Multimeter'), continue; end
        try
            mv = get_param(b,'MaskValues'); mn = get_param(b,'MaskNames');
            s = sprintf('  [%s] %s :: ', bt, nm);
            for j = 1:min(numel(mn),8)
                v = mv{j}; if numel(v) > 35, v = [v(1:35) '..']; end
                s = [s sprintf('%s=%s; ', mn{j}, v)];
            end
            fprintf('%s\n', s);
        catch, end
    else
        dump_plain(b, bt, nm);
    end
end
% SampleTime distribution
st_map = containers.Map;
blks2 = find_system(mdl,'LookUnderMasks','all','FollowLinks','on');
for i = 2:numel(blks2)
    try
        st = get_param(blks2{i},'SampleTime');
        if ischar(st) || isstring(st)
            key = char(st); if numel(key) > 12, key = key(1:12); end
            if st_map.isKey(key), st_map(key) = st_map(key) + 1; else, st_map(key) = 1; end
        end
    catch, end
end
ks = keys(st_map); s = 'SampleTime: ';
for i = 1:numel(ks), s = [s sprintf('%s x%d, ', ks{i}, st_map(ks{i}))]; end
fprintf('%s\n', s);
end

%% Basic block parameters
function dump_plain(b, bt, nm)
switch bt
    case 'Constant'
        try, fprintf('  [Constant] %s = %s\n', nm, get_param(b,'Value')); catch, end
    case 'Gain'
        try, fprintf('  [Gain] %s = %s\n', nm, get_param(b,'Gain')); catch, end
    case 'Bias'
        try, fprintf('  [Bias] %s = %s\n', nm, get_param(b,'Bias')); catch, end
    case 'Saturate'
        try, fprintf('  [Saturate] %s: lo=%s hi=%s\n', nm, get_param(b,'LowerLimit'), get_param(b,'UpperLimit')); catch, end
    case 'Switch'
        try, fprintf('  [Switch] %s: thr=%s criteria=%s\n', nm, get_param(b,'Threshold'), get_param(b,'Criteria')); catch, end
    case 'ZeroOrderHold'
        try, fprintf('  [ZeroOrderHold] %s: Ts=%s\n', nm, get_param(b,'SampleTime')); catch, end
    case 'DiscreteIntegrator'
        try
            g = get_param(b,'gainval');  % R2024b parameter name
            fprintf('  [DiscreteIntegrator] %s: gain=%s IC=%s\n', nm, g, get_param(b,'InitialCondition'));
        catch
            try, fprintf('  [DiscreteIntegrator] %s: gain=%s IC=%s\n', nm, get_param(b,'GainValue'), get_param(b,'InitialCondition')); catch, end
        end
    case 'Sum'
        try, fprintf('  [Sum] %s: signs=%s\n', nm, get_param(b,'Inputs')); catch, end
    case 'ToWorkspace'
        try, fprintf('  [ToWorkspace] %s: var=%s\n', nm, get_param(b,'VariableName')); catch, end
    case 'RepeatingSequence'
        try
            y = get_param(b,'OutValues');  % older releases
            t = get_param(b,'TimeValues');
            fprintf('  [RepeatingSequence] %s: t=%s y=%s\n', nm, mat2str(t), mat2str(y));
        catch
            try
                fprintf('  [RepeatingSequence] %s: t=%s y=%s\n', nm, mat2str(get_param(b,'rep_seq_t')), mat2str(get_param(b,'rep_seq_y')));
            catch, end
        end
    case {'SubSystem','Scope','From','Goto','Logic','RelationalOperator','DigitalClock','Clock','Display','Outport','Inport','Mux','Demux'}
        % noise blocks, skip
    otherwise
        try, fprintf('  [%s] %s\n', bt, nm); catch, end
end
end
