import { FlowDiagram } from "#/components/interactive/FlowDiagram";
import { SectionHeading } from "#/components/ui/SectionHeading";
import { flowCopy } from "#/content/flow";
import styles from "./HowItWorks.module.css";

export function HowItWorks() {
	return (
		<section className="section" id="how" aria-labelledby="how-title">
			<div className="container">
				<SectionHeading
					eyebrow="How it works"
					title={flowCopy.title}
					lede={flowCopy.intro}
					id="how-title"
				/>
				<div data-reveal>
					<FlowDiagram />
				</div>
				<p className={styles.footer} data-reveal>
					{flowCopy.footer}
				</p>
			</div>
		</section>
	);
}
