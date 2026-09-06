import styles from "./Kbd.module.css";

interface KbdProps {
	readonly children: string;
}

export function Kbd({ children }: KbdProps) {
	return <kbd className={styles.kbd}>{children}</kbd>;
}
