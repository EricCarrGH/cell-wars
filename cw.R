require(utils)
require(ggplot2)
require(dplyr)
require(ggthemes)

cw = read.csv("~/Documents/cw/cw_marginal.csv") %>% 
  filter(difficulty != 'easy') %>%
  mutate(difficulty = factor(difficulty, levels = c("normal","hard","insane")),
         numCells = ifelse(size=='S',10,
                ifelse(size=='M',15,
                ifelse(size=='L',25,
                ifelse(size=='XL',40,
                ifelse(size=='C60',60,
                ifelse(size=='C80',80,100)))))),
         N.2 = N + 2,
         positive.2 = positive + 1,
         negative.2 = N.2 - positive.2,
         negative = N - positive,
         actual = positive / (positive + negative),
         actual.2 = positive.2 / (positive.2 + negative.2),
         startingNum = ifelse(starting=='solo',1,ifelse(starting=='pairs',2,numCells / 5)),
         startingPct = startingNum / numCells * 100
)

marginals = cw %>%
  select(
    numCells,
    difficulty,
    positive,
    N
  ) %>%
  group_by(numCells, difficulty) %>%
  mutate(
    sumPositive = sum(positive),
    gamesPlayed = sum(N),
    marginalRate = sumPositive / gamesPlayed
  ) %>%
  select(-positive,-N) %>%
  rename(actualGamesPlayed = gamesPlayed) %>%
  slice(1)

marginals.beta = marginals %>%
  select(-marginalRate) %>%
  merge(seq(from=0, to=1, by=0.01), by=NULL) %>%
  mutate(B = (actualGamesPlayed - sumPositive)) %>%
  select(-actualGamesPlayed) %>%
  rename(x = y, A = sumPositive) %>%
  mutate(beta.y = dbeta(x, A+1, B+1)) %>%
  group_by(numCells, difficulty) %>%
  mutate(
    max.y = max(beta.y),
    y = beta.y / max.y
  ) %>%
  ungroup()

ggplot(data=marginals.beta, aes(x=x,y=y,color=difficulty)) + 
  coord_flip() + 
  geom_line() + 
  ggthemes::theme_economist() +
  facet_grid(~ numCells) +
  scale_y_discrete(breaks = NULL) +
  labs(title = "Likelihood of past win percentages, by map size",
       y = "Likelihood of this win percentage occurring", x = "Win percentage") +
  ggsave(file="win-percentage-likelihoods.png", width = 12, height = 8)

for(WITH.INTERACTIONS in c(FALSE,TRUE)) {
  
  formula = ifelse(WITH.INTERACTIONS, 
                   'cbind(positive.2,negative.2) ~ numCells * difficulty',
                   'cbind(positive.2,negative.2) ~ numCells + difficulty')
  
  fit = glm(data = cw, formula = as.formula(formula), family = binomial())
  
  summary(fit) # display results
  exp(cbind(OR = coef(fit), confint(fit))) # exponentiated coefficients with 95% CI
  
  to.plot.from = 10
  to.plot.to = 100
  
  to.plot = expand.grid(numCells = seq(from=to.plot.from,to=to.plot.to), startingMode = c("1", "2", "3"), difficulty = c("normal","hard","insane"))
  to.plot$startingNum = as.numeric(to.plot$startingMode)
  to.plot$startingNum = ifelse(to.plot$startingNum==3 | (to.plot$startingNum==2 & to.plot$numCells < 10), to.plot$numCells / 5, to.plot$startingNum)
  
  levels(to.plot$difficulty) = c("normal","hard","insane")
  to.plot = cbind(to.plot, predict(fit,newdata = to.plot, type = "link",se=TRUE))
  
  to.plot = within(to.plot, {
    PredictedProb <- plogis(fit)
    LL <- plogis(fit - (1.64 * se.fit))  # 1.96 is 95% CI
    UL <- plogis(fit + (1.64 * se.fit))
  })
  
  plot.save.prefix = ifelse(WITH.INTERACTIONS, 'with-interactions-', 'no-interactions-')
  
  ggplot(data=to.plot, aes(x = numCells, y = PredictedProb)) + 
    geom_ribbon(aes(ymin = LL, ymax = UL, fill = difficulty), alpha = .2) +
    geom_line(aes(color=difficulty),size=1) + 
    scale_y_continuous(breaks=seq(from=0,to=1,by=0.1),minor_breaks = waiver()) +
    scale_x_continuous(breaks=seq(from=to.plot.from,to=to.plot.to,by=10),minor_breaks = waiver()) +
    labs(title = "Win probability as a function of map parameters",
         x = "Number of map cells", y = "Win percentage\nDots represent actual games — lines are predicted") +
    geom_point(data=marginals, aes(y=marginalRate, x=numCells, color = difficulty, size = actualGamesPlayed)) +
    ggthemes::theme_economist() +
    ggsave(file=paste(plot.save.prefix,"plot.png",sep = ''), width=12, height = 8)
}
