"""平衡 108拜 训练数据，通过欠采样多数类"""
import pandas as pd

INPUT = r"d:\workspace\ShiXingXia\assets\bai108_features_binary.csv"
OUTPUT = INPUT  # 覆盖原文件

df = pd.read_csv(INPUT)
print("原始分布:")
print(df['pose'].value_counts().sort_index())

# 每类最多保留 40 个样本（对齐最少类的约 2 倍，避免过度损失）
MAX_PER_CLASS = 40

balanced = []
for pose in sorted(df['pose'].unique()):
    subset = df[df['pose'] == pose]
    if len(subset) > MAX_PER_CLASS:
        sampled = subset.sample(n=MAX_PER_CLASS, random_state=42)
    else:
        sampled = subset
    balanced.append(sampled)

df_balanced = pd.concat(balanced)
df_balanced = df_balanced.sample(frac=1, random_state=42)  # shuffle

print("\n平衡后分布:")
print(df_balanced['pose'].value_counts().sort_index())

df_balanced.to_csv(OUTPUT, index=False)
print(f"\n已保存: {OUTPUT} ({len(df_balanced)} 行)")
