import { Icon } from "#/components/ui/Icon";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { hinglish } from "#/content/intelligence";
import styles from "./Multilingual.module.css";

export function Multilingual() {
	return (
		<section
			className="section"
			id="languages"
			aria-labelledby="languages-title"
		>
			<div className={`container ${styles.grid}`}>
				<SectionHeading
					eyebrow="Hindi and Hinglish"
					title={hinglish.title}
					lede={hinglish.intro}
					id="languages-title"
				/>
				<div className={styles.card} data-reveal>
					<p className={styles.label}>You say, in Hindi</p>
					<p className={styles.spoken} lang="hi">
						{hinglish.spoken}
					</p>
					<span className={styles.arrow}>
						<Icon name="arrowRight" size={18} />
					</span>
					<p className={styles.label}>TapTalk pastes</p>
					<p className={styles.result}>{hinglish.result}</p>
					<p className={styles.caption}>{hinglish.caption}</p>
					<p className={`faint ${styles.honesty}`}>{hinglish.honesty}</p>
				</div>
			</div>
		</section>
	);
}
