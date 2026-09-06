import { useEffect, useState } from "react";
import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import styles from "./CopyCommand.module.css";

interface CopyCommandProps {
	readonly command: string;
	readonly className?: string;
}

export function CopyCommand({ command, className }: CopyCommandProps) {
	const [copied, setCopied] = useState(false);

	useEffect(() => {
		if (!copied) return;
		const timer = window.setTimeout(() => setCopied(false), 1600);
		return () => window.clearTimeout(timer);
	}, [copied]);

	const copy = () => {
		void navigator.clipboard.writeText(command).then(() => setCopied(true));
	};

	return (
		<div className={cx(styles.wrap, className)}>
			<span className={styles.prompt} aria-hidden="true">
				$
			</span>
			<code className={styles.command}>{command}</code>
			<button
				type="button"
				className={styles.copy}
				onClick={copy}
				aria-label={copied ? "Copied" : "Copy install command"}
			>
				<Icon name={copied ? "check" : "copy"} size={16} />
				<span>{copied ? "Copied" : "Copy"}</span>
			</button>
		</div>
	);
}
