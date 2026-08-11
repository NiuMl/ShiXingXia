"""
从视频中提取姿态关键点并自动分类，生成 landmarks.csv + labels.csv
供 feature_extraction.py 进一步提取特征。

用法:
    python extract_video_poses.py

输入: 视频文件 + MediaPipe Pose Landmarker 模型
输出: Data/landmarks.csv, Data/labels.csv
"""
import os
import cv2
import numpy as np
import pandas as pd
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# ======================== 配置 ========================
VIDEO_PATH = r"C:\Users\670we\Downloads\108.mp4"
MODEL_PATH = os.path.join(os.path.dirname(__file__), "pose_landmarker_lite.task")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "Data")
SAMPLE_EVERY = 2  # 每隔几帧采样一次（1=每帧都取）

# MediaPipe Pose 33 个关键点名称（顺序固定）
LANDMARK_NAMES = [
    "nose", "left_eye_inner", "left_eye", "left_eye_outer",
    "right_eye_inner", "right_eye", "right_eye_outer",
    "left_ear", "right_ear", "mouth_left", "mouth_right",
    "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
    "left_wrist", "right_wrist", "left_pinky", "right_pinky",
    "left_index", "right_index", "left_thumb", "right_thumb",
    "left_hip", "right_hip", "left_knee", "right_knee",
    "left_ankle", "right_ankle", "left_heel", "right_heel",
    "left_foot_index", "right_foot_index",
]

# 运动前缀（feature_extraction.py 用 split("_")[0] 分组）
# 命名带数字前缀，使 sorted() 后顺序固定：0=站立, 1=合掌, 2=趴下
EXERCISE_PREFIX = "bai108"
POSE_LABELS = {
    "stand": f"{EXERCISE_PREFIX}_0_stand",
    "pray": f"{EXERCISE_PREFIX}_1_pray",
    "prostrate": f"{EXERCISE_PREFIX}_2_prostrate",
}


def classify_pose(lm):
    """
    根据关键点特征规则分类当前帧。
    坐标为归一化值，y 向下递增。
    返回 pose 标签字符串；可见度不足返回 None。
    """
    # 关键可见关节
    keys = ["left_shoulder", "right_shoulder", "left_hip",
            "right_hip", "left_wrist", "right_wrist"]
    avg_vis = float(np.mean([lm[k][3] for k in keys]))
    if avg_vis < 0.3:
        return None  # 关键点可见度太低，跳过

    def mid(a, b):
        return np.array([(lm[a][0] + lm[b][0]) / 2, (lm[1][1] if False else (lm[a][1] + lm[b][1]) / 2)])

    sh_mid = np.array([(lm["left_shoulder"][0] + lm["right_shoulder"][0]) / 2,
                       (lm["left_shoulder"][1] + lm["right_shoulder"][1]) / 2])
    hip_mid = np.array([(lm["left_hip"][0] + lm["right_hip"][0]) / 2,
                        (lm["left_hip"][1] + lm["right_hip"][1]) / 2])
    wrist_mid = np.array([(lm["left_wrist"][0] + lm["right_wrist"][0]) / 2,
                          (lm["left_wrist"][1] + lm["right_wrist"][1]) / 2])

    # 身体水平度：肩-髋连线的水平分量占比
    # 站立时肩在髋正上方 → dy 大、dx 小 → ratio 接近 0
    # 趴下时身体水平 → dx 大、dy 小 → ratio 接近 1
    dx = abs(sh_mid[0] - hip_mid[0])
    dy = abs(sh_mid[1] - hip_mid[1])
    horiz_ratio = dx / (dx + dy + 1e-6)

    if horiz_ratio > 0.55:
        # 身体接近水平 → 趴下（五体投地）
        return POSE_LABELS["prostrate"]
    elif wrist_mid[1] < sh_mid[1] - 0.03:
        # 手腕明显高于肩 → 合掌（双手向上举起）
        return POSE_LABELS["pray"]
    else:
        # 直立、手在身侧 → 站立
        return POSE_LABELS["stand"]


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    base_options = python.BaseOptions(model_asset_path=MODEL_PATH)
    options = vision.PoseLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.3,
        min_pose_presence_confidence=0.3,
        min_tracking_confidence=0.3,
    )
    detector = vision.PoseLandmarker.create_from_options(options)

    cap = cv2.VideoCapture(VIDEO_PATH)
    if not cap.isOpened():
        raise RuntimeError(f"无法打开视频: {VIDEO_PATH}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"视频: {VIDEO_PATH}")
    print(f"FPS: {fps:.1f}, 总帧数: {total_frames}, 采样间隔: 每 {SAMPLE_EVERY} 帧")

    landmarks_rows = []
    labels_rows = []
    pose_id = 0
    frame_idx = 0
    stats = {POSE_LABELS["stand"]: 0, POSE_LABELS["pray"]: 0,
             POSE_LABELS["prostrate"]: 0, "skip": 0}
    # 记录每类特征分布用于调试
    feat_dist = {k: {"horiz": [], "wrist_rel": []} for k in POSE_LABELS.values()}

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frame_idx += 1
        if frame_idx % SAMPLE_EVERY != 0:
            continue

        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
        timestamp_ms = int(frame_idx / fps * 1000)

        result = detector.detect_for_video(mp_image, timestamp_ms)

        if not result.pose_landmarks:
            stats["skip"] += 1
            continue

        lms = result.pose_landmarks[0]
        lm_dict = {}
        for i, name in enumerate(LANDMARK_NAMES):
            p = lms[i]
            lm_dict[name] = (p.x, p.y, p.z, p.visibility)

        label = classify_pose(lm_dict)
        if label is None:
            stats["skip"] += 1
            continue

        # 构建 landmarks 行（33 关键点 × x/y/z）
        row = {"pose_id": pose_id}
        for name in LANDMARK_NAMES:
            x, y, z, _ = lm_dict[name]
            row[f"x_{name}"] = x
            row[f"y_{name}"] = y
            row[f"z_{name}"] = z
        landmarks_rows.append(row)
        labels_rows.append({"pose_id": pose_id, "pose": label})

        # 调试特征
        sh_mid_y = (lm_dict["left_shoulder"][1] + lm_dict["right_shoulder"][1]) / 2
        hip_mid_y = (lm_dict["left_hip"][1] + lm_dict["right_hip"][1]) / 2
        wrist_mid_y = (lm_dict["left_wrist"][1] + lm_dict["right_wrist"][1]) / 2
        sh_mid_x = (lm_dict["left_shoulder"][0] + lm_dict["right_shoulder"][0]) / 2
        hip_mid_x = (lm_dict["left_hip"][0] + lm_dict["right_hip"][0]) / 2
        dx = abs(sh_mid_x - hip_mid_x)
        dy = abs(sh_mid_y - hip_mid_y)
        feat_dist[label]["horiz"].append(dx / (dx + dy + 1e-6))
        feat_dist[label]["wrist_rel"].append(sh_mid_y - wrist_mid_y)

        stats[label] = stats.get(label, 0) + 1
        pose_id += 1

    cap.release()
    detector.close()

    # 保存
    lm_df = pd.DataFrame(landmarks_rows)
    lb_df = pd.DataFrame(labels_rows)
    lm_path = os.path.join(OUTPUT_DIR, "landmarks.csv")
    lb_path = os.path.join(OUTPUT_DIR, "labels.csv")
    lm_df.to_csv(lm_path, index=False)
    lb_df.to_csv(lb_path, index=False)

    print("\n========== 分类统计 ==========")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    print(f"  有效样本总数: {pose_id}")
    print(f"\n已保存: {lm_path} ({len(lm_df)} 行)")
    print(f"已保存: {lb_path} ({len(lb_df)} 行)")

    print("\n========== 特征分布（用于校验分类阈值）==========")
    for label, feats in feat_dist.items():
        if feats["horiz"]:
            h = np.array(feats["horiz"])
            w = np.array(feats["wrist_rel"])
            print(f"  {label}:")
            print(f"    水平占比  mean={h.mean():.3f} min={h.min():.3f} max={h.max():.3f}")
            print(f"    手腕相对高度 mean={w.mean():.3f} min={w.min():.3f} max={w.max():.3f}")


if __name__ == "__main__":
    main()
