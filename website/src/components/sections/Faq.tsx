import { Icon } from "#/components/ui/Icon";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { faq } from "#/content/faq";
import styles from "./Faq.module.css";

// Native details/summary: no JavaScript, and every answer is in the prerendered HTML.
export function Faq() {
	return (
		<section className="section" id="faq" aria-labelledby="faq-title">
			<div className={`container ${styles.wrap}`}>
				<SectionHeading
					eyebrow="FAQ"
					title="Questions people ask before they trust a dictation app."
					id="faq-title"
				/>
				<div className={styles.list}>
					{faq.map((item, index) => (
						<details
							key={item.question}
							className={styles.item}
							data-reveal
							open={index === 0}
						>
							<summary className={styles.question}>
								<span>{item.question}</span>
								<Icon name="arrowRight" size={16} className={styles.chevron} />
							</summary>
							<p className={styles.answer}>{item.answer}</p>
						</details>
					))}
				</div>
			</div>
		</section>
	);
}
