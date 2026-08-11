import pandas as pd
import numpy as np
import os
from collections import defaultdict

# ========================
# Paths
# ========================
landmarks_path = "Data/landmarks.csv"
labels_path = "Data/labels.csv"
output_dir = "Data2"

# ========================
# Load data
# ========================
df_landmarks = pd.read_csv(landmarks_path)
df_labels = pd.read_csv(labels_path)
df = pd.merge(df_landmarks, df_labels, on="pose_id")

# Detect all base exercise types (e.g. "pushups", "squats", "situp")
exercise_groups = defaultdict(list)
for pose in df["pose"].unique():
    base = pose.split("_")[0]
    exercise_groups[base].append(pose)

print("🔍 Detected exercise groups:")
for k, v in exercise_groups.items():
    print(f" - {k}: {v}")

# ==========================================================
# Normalization + Feature Extraction 
# ==========================================================

def normalize_landmarks(row, df_cols):
    hips = np.array([
        [row["x_left_hip"], row["y_left_hip"], row["z_left_hip"]],
        [row["x_right_hip"], row["y_right_hip"], row["z_right_hip"]],
    ])
    shoulders = np.array([
        [row["x_left_shoulder"], row["y_left_shoulder"], row["z_left_shoulder"]],
        [row["x_right_shoulder"], row["y_right_shoulder"], row["z_right_shoulder"]],
    ])
    center = hips.mean(axis=0)
    landmarks = {}
    for base in set(col.split("_", 1)[1] for col in df_cols if col.startswith("x_")):
        landmarks[base] = np.array([
            row[f"x_{base}"] - center[0],
            row[f"y_{base}"] - center[1],
            row[f"z_{base}"] - center[2],
        ])
    torso_len = np.linalg.norm(shoulders.mean(axis=0) - hips.mean(axis=0))
    scale = torso_len if torso_len != 0 else 1.0
    for k in landmarks:
        landmarks[k] /= scale
    return landmarks

def dist(a, b): return np.linalg.norm(a - b)
def angle(a, b, c):
    ab, cb = a - b, c - b
    dot = np.dot(ab, cb)
    return np.degrees(np.arccos(dot / (np.linalg.norm(ab) * np.linalg.norm(cb))))
def avg(*points): return np.mean(points, axis=0)

def extract_features(landmarks):
    get = lambda name: landmarks[name]
    feats = {}
    # Distances
    feats["left_shoulder_left_wrist"] = dist(get("left_shoulder"), get("left_wrist"))
    feats["right_shoulder_right_wrist"] = dist(get("right_shoulder"), get("right_wrist"))
    feats["left_hip_left_ankle"] = dist(get("left_hip"), get("left_ankle"))
    feats["right_hip_right_ankle"] = dist(get("right_hip"), get("right_ankle"))
    feats["left_hip_left_wrist"] = dist(get("left_hip"), get("left_wrist"))
    feats["right_hip_right_wrist"] = dist(get("right_hip"), get("right_wrist"))
    feats["left_shoulder_left_ankle"] = dist(get("left_shoulder"), get("left_ankle"))
    feats["right_shoulder_right_ankle"] = dist(get("right_shoulder"), get("right_ankle"))
    feats["left_hip_right_wrist"] = dist(get("left_hip"), get("right_wrist"))
    feats["right_hip_left_wrist"] = dist(get("right_hip"), get("left_wrist"))
    feats["left_elbow_right_elbow"] = dist(get("left_elbow"), get("right_elbow"))
    feats["left_knee_right_knee"] = dist(get("left_knee"), get("right_knee"))
    feats["left_wrist_right_wrist"] = dist(get("left_wrist"), get("right_wrist"))
    feats["left_ankle_right_ankle"] = dist(get("left_ankle"), get("right_ankle"))
    feats["left_hip_avg_left_wrist_left_ankle"] = dist(get("left_hip"), avg(get("left_wrist"), get("left_ankle")))
    feats["right_hip_avg_right_wrist_right_ankle"] = dist(get("right_hip"), avg(get("right_wrist"), get("right_ankle")))

    # Angles
    feats["right_elbow_right_shoulder_right_hip"] = angle(get("right_elbow"), get("right_shoulder"), get("right_hip"))
    feats["left_elbow_left_shoulder_left_hip"] = angle(get("left_elbow"), get("left_shoulder"), get("left_hip"))
    feats["right_knee_mid_hip_left_knee"] = angle(get("right_knee"), avg(get("left_hip"), get("right_hip")), get("left_knee"))
    feats["right_hip_right_knee_right_ankle"] = angle(get("right_hip"), get("right_knee"), get("right_ankle"))
    feats["left_hip_left_knee_left_ankle"] = angle(get("left_hip"), get("left_knee"), get("left_ankle"))
    feats["right_wrist_right_elbow_right_shoulder"] = angle(get("right_wrist"), get("right_elbow"), get("right_shoulder"))
    feats["left_wrist_left_elbow_left_shoulder"] = angle(get("left_wrist"), get("left_elbow"), get("left_shoulder"))
    return feats

# ==========================================================
# Process each exercise group
# ==========================================================
os.makedirs(output_dir, exist_ok=True)

for exercise, poses in exercise_groups.items():
    if len(poses) < 2:
        continue

    df_ex = df[df["pose"].isin(poses)].reset_index(drop=True)

    # Assign numeric labels based on the unique poses (supports 2+ states)
    # 用 sorted 保证标签编号稳定且可控（配合标签命名中的数字前缀）
    label_map = {pose: i for i, pose in enumerate(sorted(poses))}
    df_ex["pose"] = df_ex["pose"].map(label_map)

    results = []
    for _, row in df_ex.iterrows():
        norm_landmarks = normalize_landmarks(row, df.columns)
        feats = extract_features(norm_landmarks)
        feats["pose"] = int(row["pose"])
        results.append(feats)

    features_df = pd.DataFrame(results)
    out_path = os.path.join(output_dir, f"{exercise}_features_binary.csv")
    features_df.to_csv(out_path, index=False)
    print(f"Saved {len(features_df)} samples to {out_path}")


