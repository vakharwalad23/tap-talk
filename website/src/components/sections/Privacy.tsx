import type { CSSVars } from "#/components/ui/cx";
import { Icon } from "#/components/ui/Icon";
import { SectionHeading } from "#/components/ui/SectionHeading";
import {
	permissions,
	permissionsNote,
	privacyChecklist,
} from "#/content/privacy";
import { site } from "#/content/site";
import styles from "./Privacy.module.css";

export function Privacy() {
	return (
		<section className="section" id="privacy" aria-labelledby="privacy-title">
			<div className="container">
				<SectionHeading
					eyebrow="Privacy"
					title="Privacy is the default, not a setting."
					lede="Nothing about how TapTalk handles your voice depends on a toggle you have to find. This is how it ships."
					id="privacy-title"
				/>
				<ul className={styles.list}>
					{privacyChecklist.map((item, index) => {
						const vars: CSSVars = { "--reveal-delay": `${index * 50}ms` };
						return (
							<li
								key={item.title}
								className={styles.item}
								data-reveal
								style={vars}
							>
								<span className={styles.check}>
									<Icon name="check" size={14} />
								</span>
								<div>
									<h3>{item.title}</h3>
									<p>
										{item.body}
										{item.title === "Falsifiable" ? (
											<>
												{" "}
												<a
													href={site.repoUrl}
													target="_blank"
													rel="noopener noreferrer"
												>
													Read the source.
												</a>
											</>
										) : null}
									</p>
								</div>
							</li>
						);
					})}
				</ul>
				<div className={styles.permissions} data-reveal>
					<h3>Two permissions, and only two</h3>
					<table>
						<thead>
							<tr>
								<th scope="col">Permission</th>
								<th scope="col">Why</th>
								<th scope="col">When</th>
							</tr>
						</thead>
						<tbody>
							{permissions.map((permission) => (
								<tr key={permission.name}>
									<td>{permission.name}</td>
									<td>{permission.why}</td>
									<td>{permission.when}</td>
								</tr>
							))}
						</tbody>
					</table>
					<p className="muted">{permissionsNote}</p>
				</div>
			</div>
		</section>
	);
}
