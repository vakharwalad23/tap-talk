import { cx } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import app from "./app.module.css";

function Checkbox({ on }: { readonly on: boolean }) {
	return (
		<span className={cx(app.checkbox, on && app.checkboxOn)} aria-hidden="true">
			{on ? <Icon name="check" size={10} strokeWidth={3} /> : null}
		</span>
	);
}

interface TileProps {
	readonly title: string;
	readonly sub: string;
	readonly active?: boolean;
}

function Tile({ title, sub, active = false }: TileProps) {
	return (
		<span className={cx(app.tile, active && app.tileActive)}>
			<strong>{title}</strong>
			<span>{sub}</span>
		</span>
	);
}

export function SettingsPage() {
	return (
		<div>
			<div className={app.header}>
				<h3 className={app.h1}>Settings</h3>
				<p className={app.sub}>Engine, hotkey, and startup</p>
			</div>

			<section className={app.section}>
				<div className={app.sectionLabel}>Transcription engine</div>
				<div className={app.card}>
					<div className={app.tiles}>
						<Tile title="Local" sub="On-device, private" active />
						<Tile title="Cloud" sub="OpenAI Whisper API" />
					</div>
					<div className={app.divider} />
					<div className={app.label}>Local model</div>
					<div className={app.tiles}>
						<Tile title="Parakeet TDT" sub="English + 24 European" active />
						<Tile title="Nemotron 3.5" sub="Hindi + 100 languages" />
					</div>
					<div className={app.divider} />
					<div className={app.row}>
						<span className={app.rowLabel}>
							Live typing (stream as you speak)
						</span>
						<Checkbox on={false} />
					</div>
					<p className={app.hint}>
						Types words live into the focused app as Parakeet recognizes them.
						Uses the Parakeet Realtime (EOU) model. Off in Smart Mode.
					</p>
				</div>
			</section>

			<section className={app.section}>
				<div className={app.sectionLabel}>Startup</div>
				<div className={app.card}>
					<div className={app.row}>
						<span className={app.rowLabel}>Launch at login</span>
						<Checkbox on />
					</div>
				</div>
			</section>

			<section className={app.section}>
				<div className={app.sectionLabel}>Hotkey</div>
				<div className={app.card}>
					<div className={app.row}>
						<span className={app.rowLabel}>Push-to-talk key</span>
						<span className={app.bordered}>Right Cmd</span>
					</div>
					<div className={app.divider} />
					<span className={cx(app.bordered, app.borderedMuted)}>
						Reset to Right Cmd
					</span>
				</div>
			</section>
		</div>
	);
}
