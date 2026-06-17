function gen_sp_from_yolo_labels_reproducible()
%GEN_SP_FROM_YOLO_LABELS_REPRODUCIBLE
% Generate synthetic SP maps from YOLO-format UAV labels.
%
% This script is intended to reproduce the SP-map generation protocol used in
% the paper:
%   1) ARD100 provides RGB images and YOLO labels, but no synchronized RF SP.
%   2) Synthetic SP maps are generated from the RGB target center with
%      controllable azimuth/elevation perturbations.
%   3) Training perturbation: |dAz| and |dEl| are independently sampled from
%      U(0.5 deg, 2.0 deg), with random signs.
%   4) Testing perturbation: |dAz| = |dEl| = e, where e is selected from
%      [0.5, 1.0, 1.5, 2.0, 2.3] deg, with random signs.
%   5) The per-axis error e is not divided by sqrt(2). Thus, the overall
%      equivalent angular magnitude is sqrt(dAz^2 + dEl^2).
%
% YOLO label format:
%   cls x_center y_center width height
% where all coordinates are normalized to [0, 1].
%
% Output:
%   - A pseudo-color SP map in PNG format for each YOLO label file.
%   - A MAT metadata file containing target centers, sampled perturbations,
%     pixel offsets, shifted SP-peak coordinates, and configuration.

%% ========================= User configuration =========================
% Use relative paths for reproducibility. Modify these paths before running.
labelDir = 'C:\Users\18454\xwechat_files\wxid_vl6zrgw0muli22_ddde\msg\file\2025-09\test_labels';  % folder containing YOLO .txt files

% Output folders. They are placed under the same parent directory as labelDir.
dataRoot = fileparts(labelDir);
outRoot  = fullfile(dataRoot, 'synthetic_sp_maps');  % output folder for PNG SP maps
matRoot  = fullfile(dataRoot, 'synthetic_sp_meta');  % output folder for MAT metadata

% Original image resolution used for physical angular-to-pixel projection.
imgW = 1920;
imgH = 1080;

% Horizontal field of view. The vertical FOV is derived from the aspect ratio
% under a pinhole camera model with square pixels.
HFOVdeg = 111;

% Generation mode:
%   'train': random per-axis errors sampled from trainErrDegRange
%   'test' : fixed per-axis errors from testErrDegList
mode = 'train';

% SP degradation condition:
%   'default': default synthetic SP map
%   'noisy'  : increased background noise floor
%   'false1' : one spurious SP-like cluster
%   'false3' : three spurious SP-like clusters
spCondition = 'default';

% Reproducibility. Use a fixed seed instead of rng('shuffle').
randomSeed = 2026;

% Angular-error settings. The error is defined per axis.
trainErrDegRange = [0.5, 2.0];
testErrDegList   = [0.5, 1.0, 1.5, 2.0, 2.3];

% SP appearance settings.
peakAmp      = 1.00;  % target-related main-lobe amplitude
sidelobeAmp  = 0.18;  % local weak sidelobe-like response amplitude
noiseAmp     = 0.08;  % default uniform background noise amplitude
noisyNoiseAmp = 0.16; % noise amplitude for the noisy-SP setting
smoothSigma  = 2.0;   % Gaussian smoothing sigma in pixels
gammaPow     = 0.7;   % pseudo-color contrast control

% Main-lobe width rule:
% sigma = clip(sigmaK * max(bbox_w, bbox_h), sigmaMin, sigmaMax)
sigmaMin = 5;
sigmaMax = 20;
sigmaK   = 0.30;

% Spurious SP-cluster settings for false1/false3.
% False peaks are generated using the same SP-cluster rule as target-related
% SP peaks, including a main lobe and two weak local sidelobe-like responses.
falsePeakAmp = 0.70;  % amplitude of the false main lobe relative to peakAmp
falseMinDist = 80;    % minimum distance from target-related SP peaks in pixels
maxTryFalsePos = 200; % maximum attempts for sampling a false peak location

saveMeta = true;
saveConfigFile = true;
%% =====================================================================

rng(randomSeed, 'twister');

mkdir_if_needed(outRoot);
mkdir_if_needed(matRoot);

% Camera intrinsics from HFOV and image width.
HFOV = deg2rad(HFOVdeg);
fx = (imgW / 2) / tan(HFOV / 2);
VFOV = 2 * atan((imgH / imgW) * tan(HFOV / 2));
fy = (imgH / 2) / tan(VFOV / 2);

fprintf('[Info] fx = %.2f px, fy = %.2f px, HFOV = %.1f deg, VFOV = %.1f deg\n', ...
    fx, fy, HFOVdeg, rad2deg(VFOV));
fprintf('[Info] mode = %s, spCondition = %s, seed = %d\n', mode, spCondition, randomSeed);

files = dir(fullfile(labelDir, '*.txt'));
if isempty(files)
    error('No .txt label files found in: %s', labelDir);
end

cmap = get_colormap_256();

config = struct();
config.labelDir = labelDir;
config.outRoot = outRoot;
config.matRoot = matRoot;
config.imgW = imgW;
config.imgH = imgH;
config.HFOVdeg = HFOVdeg;
config.VFOVdeg = rad2deg(VFOV);
config.fx = fx;
config.fy = fy;
config.mode = mode;
config.spCondition = spCondition;
config.randomSeed = randomSeed;
config.trainErrDegRange = trainErrDegRange;
config.testErrDegList = testErrDegList;
config.peakAmp = peakAmp;
config.sidelobeAmp = sidelobeAmp;
config.noiseAmp = noiseAmp;
config.noisyNoiseAmp = noisyNoiseAmp;
config.smoothSigma = smoothSigma;
config.gammaPow = gammaPow;
config.sigmaMin = sigmaMin;
config.sigmaMax = sigmaMax;
config.sigmaK = sigmaK;
config.falsePeakAmp = falsePeakAmp;
config.falseMinDist = falseMinDist;

if saveConfigFile
    save(fullfile(matRoot, 'sp_generation_config.mat'), '-struct', 'config');
end

switch lower(mode)
    case 'train'
        outDir = fullfile(outRoot, spCondition, 'train');
        matDir = fullfile(matRoot, spCondition, 'train');
        mkdir_if_needed(outDir);
        mkdir_if_needed(matDir);

        for i = 1:numel(files)
            f = files(i).name;
            inPath = fullfile(labelDir, f);
            baseName = erase(f, '.txt');
            outPath = fullfile(outDir, [baseName, '.png']);
            metaPath = fullfile(matDir, [baseName, '.mat']);

            [heat, meta] = build_sp_heatmap_from_label(inPath, imgW, imgH, fx, fy, ...
                'train', trainErrDegRange, [], spCondition, peakAmp, sidelobeAmp, ...
                noiseAmp, noisyNoiseAmp, sigmaK, sigmaMin, sigmaMax, smoothSigma, ...
                falsePeakAmp, falseMinDist, maxTryFalsePos);

            rgb = heat_to_rgb(heat, cmap, gammaPow);
            imwrite(rgb, outPath);

            if saveMeta
                meta.config = config;
                save(metaPath, '-struct', 'meta');
            end
        end

        fprintf('[Done] Train SP maps generated: %d files -> %s\n', numel(files), outDir);

    case 'test'
        for e = 1:numel(testErrDegList)
            errDeg = testErrDegList(e);
            errName = sprintf('err_%0.1fdeg', errDeg);

            outDir = fullfile(outRoot, spCondition, 'test', errName);
            matDir = fullfile(matRoot, spCondition, 'test', errName);
            mkdir_if_needed(outDir);
            mkdir_if_needed(matDir);

            for i = 1:numel(files)
                f = files(i).name;
                inPath = fullfile(labelDir, f);
                baseName = erase(f, '.txt');
                outPath = fullfile(outDir, [baseName, '.png']);
                metaPath = fullfile(matDir, [baseName, '.mat']);

                [heat, meta] = build_sp_heatmap_from_label(inPath, imgW, imgH, fx, fy, ...
                    'test', [], errDeg, spCondition, peakAmp, sidelobeAmp, ...
                    noiseAmp, noisyNoiseAmp, sigmaK, sigmaMin, sigmaMax, smoothSigma, ...
                    falsePeakAmp, falseMinDist, maxTryFalsePos);

                rgb = heat_to_rgb(heat, cmap, gammaPow);
                imwrite(rgb, outPath);

                if saveMeta
                    meta.config = config;
                    save(metaPath, '-struct', 'meta');
                end
            end

            fprintf('[Done] Test SP maps generated: err = %.1f deg -> %s\n', errDeg, outDir);
        end

    otherwise
        error('mode must be ''train'' or ''test''.');
end

end

%% ========================= Core functions =========================

function [heat, meta] = build_sp_heatmap_from_label(labelPath, W, H, fx, fy, mode, ...
    trainRangeDeg, testErrDeg, spCondition, peakAmp, sidelobeAmp, noiseAmp, noisyNoiseAmp, ...
    sigmaK, sigmaMin, sigmaMax, smoothSigma, falsePeakAmp, falseMinDist, maxTryFalsePos)

targets = read_yolo_targets(labelPath);

xv = single(0:W-1);
yv = single(0:H-1);
heat = zeros(H, W, 'single');

numTargets = size(targets, 1);
u_rgb_all = zeros(numTargets, 1);
v_rgb_all = zeros(numTargets, 1);
u_sp_all  = zeros(numTargets, 1);
v_sp_all  = zeros(numTargets, 1);
du_px_all = zeros(numTargets, 1);
dv_px_all = zeros(numTargets, 1);
dAz_all   = zeros(numTargets, 1);
dEl_all   = zeros(numTargets, 1);
sigma_all = zeros(numTargets, 1);

if numTargets > 0
    for t = 1:numTargets
        xc = targets(t, 1);
        yc = targets(t, 2);
        bwNorm = targets(t, 3);
        bhNorm = targets(t, 4);

        % RGB target center in the original image coordinate system.
        u = xc * W;
        v = yc * H;
        bw = bwNorm * W;
        bh = bhNorm * H;

        sigma = sigmaK * max(bw, bh);
        sigma = min(max(sigma, sigmaMin), sigmaMax);

        % Per-axis angular perturbation.
        switch lower(mode)
            case 'train'
                dAz = sample_signed_uniform(trainRangeDeg(1), trainRangeDeg(2));
                dEl = sample_signed_uniform(trainRangeDeg(1), trainRangeDeg(2));
            case 'test'
                dAz = testErrDeg * random_sign();
                dEl = testErrDeg * random_sign();
            otherwise
                error('mode must be train or test.');
        end

        % Angular perturbation to pixel offset.
        % No sqrt(2) normalization is applied.
        du = fx * tan(deg2rad(dAz));
        dv = fy * tan(deg2rad(dEl));

        u2 = min(max(u + du, 0), W - 1);
        v2 = min(max(v + dv, 0), H - 1);

        heat = add_sp_cluster(heat, xv, yv, u2, v2, sigma, peakAmp, sidelobeAmp);

        u_rgb_all(t) = u;
        v_rgb_all(t) = v;
        u_sp_all(t) = u2;
        v_sp_all(t) = v2;
        du_px_all(t) = du;
        dv_px_all(t) = dv;
        dAz_all(t) = dAz;
        dEl_all(t) = dEl;
        sigma_all(t) = sigma;
    end
end

% Spurious SP-like peaks for degraded-SP experiments.
numFalseClusters = parse_false_cluster_number(spCondition);
false_coords = zeros(numFalseClusters, 2);
false_sigma = zeros(numFalseClusters, 1);

for k = 1:numFalseClusters
    if isempty(sigma_all)
        sigmaF = sigmaMin + (sigmaMax - sigmaMin) * rand();
        targetPeaks = [];
    else
        sigmaF = sigma_all(randi(numel(sigma_all)));
        targetPeaks = [u_sp_all, v_sp_all];
    end

    [uf, vf] = sample_false_peak_location(W, H, targetPeaks, falseMinDist, maxTryFalsePos);
    heat = add_sp_cluster(heat, xv, yv, uf, vf, sigmaF, falsePeakAmp * peakAmp, sidelobeAmp);

    false_coords(k, :) = [uf, vf];
    false_sigma(k) = sigmaF;
end

% Background noise. Noisy-SP uses a higher noise floor.
switch lower(spCondition)
    case 'noisy'
        noiseAmpEff = noisyNoiseAmp;
    otherwise
        noiseAmpEff = noiseAmp;
end

heat = heat + noiseAmpEff * rand(H, W, 'single');

% Gaussian smoothing, normalization.
G = gaussian_kernel_2d(smoothSigma);
heat = conv2(heat, G, 'same');

heat = heat - min(heat(:));
mx = max(heat(:));
if mx > 0
    heat = heat / mx;
end

% Metadata.
meta = struct();
meta.labelPath = labelPath;
meta.targets = targets;        % [x_center y_center width height], normalized
meta.u_rgb = u_rgb_all;        % RGB target center, original pixel coordinate
meta.v_rgb = v_rgb_all;
meta.u_sp = u_sp_all;          % shifted SP peak coordinate, original pixel coordinate
meta.v_sp = v_sp_all;
meta.du_px = du_px_all;
meta.dv_px = dv_px_all;
meta.dAz_deg = dAz_all;
meta.dEl_deg = dEl_all;
meta.sigma = sigma_all;
meta.spCondition = spCondition;
meta.false_coords = false_coords;
meta.false_sigma = false_sigma;
meta.noiseAmpUsed = noiseAmpEff;
meta.perAxisErrorNote = 'dAz and dEl are defined per axis. No sqrt(2) normalization is applied.';
end

function targets = read_yolo_targets(labelPath)
lines = readlines(labelPath);
lines = strip(lines);
lines(lines == "") = [];

targets = [];
for k = 1:numel(lines)
    parts = split(lines(k));
    if numel(parts) ~= 5
        continue;
    end

    cls = str2double(parts(1)); %#ok<NASGU>
    x = str2double(parts(2));
    y = str2double(parts(3));
    w = str2double(parts(4));
    h = str2double(parts(5));

    if any(isnan([x, y, w, h]))
        continue;
    end

    targets = [targets; x, y, w, h]; %#ok<AGROW>
end
end

function heat = add_sp_cluster(heat, xv, yv, u0, v0, sigma, mainAmp, sidelobeAmp)
% Add one SP-like cluster: one main Gaussian-like lobe and two weak local
% sidelobe-like responses.

gX = exp(-((xv - single(u0)).^2) / (2 * sigma^2));
gY = exp(-((yv - single(v0)).^2) / (2 * sigma^2));
blob = gY(:) * gX(:).';
heat = heat + mainAmp * single(blob);

[H, W] = size(heat);

for s = 1:2
    off_r = 0.9 * sigma * (0.6 + 0.8 * rand());
    off_a = 2 * pi * rand();
    us = min(max(u0 + off_r * cos(off_a), 0), W - 1);
    vs = min(max(v0 + off_r * sin(off_a), 0), H - 1);

    sigma2 = sigma * (1.6 + 0.6 * rand());
    gX2 = exp(-((xv - single(us)).^2) / (2 * sigma2^2));
    gY2 = exp(-((yv - single(vs)).^2) / (2 * sigma2^2));
    blob2 = gY2(:) * gX2(:).';
    heat = heat + (sidelobeAmp * mainAmp) * single(blob2);
end
end

function n = parse_false_cluster_number(spCondition)
switch lower(spCondition)
    case 'false1'
        n = 1;
    case 'false3'
        n = 3;
    otherwise
        n = 0;
end
end

function [u, v] = sample_false_peak_location(W, H, targetPeaks, minDist, maxTry)
if isempty(targetPeaks)
    u = (W - 1) * rand();
    v = (H - 1) * rand();
    return;
end

u = (W - 1) * rand();
v = (H - 1) * rand();

for k = 1:maxTry
    candU = (W - 1) * rand();
    candV = (H - 1) * rand();
    dist = sqrt((targetPeaks(:,1) - candU).^2 + (targetPeaks(:,2) - candV).^2);

    if all(dist >= minDist)
        u = candU;
        v = candV;
        return;
    end
end
end

function val = sample_signed_uniform(a, b)
mag = a + (b - a) * rand();
val = mag * random_sign();
end

function s = random_sign()
if rand() < 0.5
    s = -1;
else
    s = 1;
end
end

function rgb = heat_to_rgb(heat01, cmap, gammaPow)
heat01 = max(0, min(1, heat01));
heat01 = heat01 .^ gammaPow;
idx = uint16(floor(heat01 * 255)) + 1;
rgb = ind2rgb(idx, cmap);
rgb = im2uint8(rgb);
end

function G = gaussian_kernel_2d(sigma)
sigma = max(sigma, 0.1);
ks = max(3, ceil(6 * sigma));
if mod(ks, 2) == 0
    ks = ks + 1;
end
r = floor(ks / 2);
[x, y] = meshgrid(-r:r, -r:r);
G = exp(-(x.^2 + y.^2) / (2 * sigma^2));
G = G / sum(G(:));
end

function cmap = get_colormap_256()
try
    cmap = turbo(256);
catch
    try
        cmap = parula(256);
    catch
        cmap = jet(256);
    end
end
end

function mkdir_if_needed(folderPath)
if ~exist(folderPath, 'dir')
    mkdir(folderPath);
end
end
