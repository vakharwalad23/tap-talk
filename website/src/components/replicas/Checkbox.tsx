import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import app from "./app.module.css";

interface CheckboxProps {
	readonly on: boolean;
}

export function Checkbox({ on }: CheckboxProps) {
	return (
		<span className={cx(app.checkbox, on && app.checkboxOn)} aria-hidden="true">
			{on ? <Icon name="check" size={10} strokeWidth={3} /> : null}
		</span>
	);
}
