import { useState } from "react";
import { type CSSVars, cx } from "#/components/ui/cx";
import { flowCopy, flowNodes } from "#/content/flow";
import styles from "./FlowDiagram.module.css";

export function FlowDiagram() {
	const first = flowNodes[0];
	const [selectedId, setSelectedId] = useState(first?.id ?? "");
	const [smart, setSmart] = useState(true);
	const selected = flowNodes.find((node) => node.id === selectedId) ?? first;
	const trackVars: CSSVars = { "--count": flowNodes.length };

	return (
		<div className={styles.diagram}>
			<div className={styles.track} style={trackVars}>
				<div className={styles.line} aria-hidden="true" />
				<div className={styles.packet} aria-hidden="true" />
				{flowNodes.map((node, index) => {
					const dimmed = node.optional === true && !smart;
					const nodeVars: CSSVars = { "--i": index };
					return (
						<button
							key={node.id}
							type="button"
							style={nodeVars}
							className={cx(
								styles.node,
								dimmed && styles.dimmed,
								node.id === selectedId && styles.selected,
							)}
							aria-pressed={node.id === selectedId}
							onClick={() => setSelectedId(node.id)}
						>
							<span className={styles.head}>
								<span className={styles.step}>{index + 1}</span>
								<span className={styles.layer}>
									{node.layer === "rust" ? "Rust" : "Swift + ANE"}
								</span>
							</span>
							<span className={styles.title}>{node.title}</span>
							<span className={styles.summary}>{node.summary}</span>
							{node.optional ? (
								<span className={styles.optional}>Smart key only</span>
							) : null}
						</button>
					);
				})}
			</div>

			<div className={styles.below}>
				<div className={styles.detail} aria-live="polite">
					{selected ? (
						<>
							<strong>{selected.title}</strong>
							<p>{selected.detail}</p>
						</>
					) : null}
				</div>
				<div className={styles.controls}>
					<label className={styles.toggle}>
						<input
							type="checkbox"
							checked={smart}
							onChange={(event) => setSmart(event.target.checked)}
						/>
						<span>Smart Mode adds the local rewrite step</span>
					</label>
					<p className="faint">
						Rust owns the audio path. Swift and the Neural Engine own
						recognition, the rewrite, and the paste.
					</p>
					<p className="faint">{flowCopy.liveTypingNote}</p>
				</div>
			</div>
		</div>
	);
}
