#### Mark-recapture JAGS Model, slightly modified from Riecke et al. 2018 ####

# Front-end -----
# . Library load ----
library(R2jags)

# Data manipulation ----
# . Data read and definitions ----

#PIT Tag Data
#d<-read.csv("LWR_CH_QUPE_PIT.csv",header=F)
# or
#d<-read.csv("LWR_CH_QUPU_PIT.csv",header=F)
# or
#d<-read.csv("UPR_CH_QUPE_PIT.csv",header=F)
# or
#d<-read.csv("UPR_CH_QUPU_PIT.csv",header=F)

#Shellfish Tag Data
#d<-read.csv("LWR_CH_QUPE_FLOY.csv",header=F)
# or
#d<-read.csv("LWR_CH_QUPU_FLOY.csv",header=F)
# or
#d<-read.csv("LWR_CH_AMPL_FLOY.csv",header=F)
# or
#d<-read.csv("UPR_CH_QUPE_FLOY.csv",header=F)
# or
#d<-read.csv("UPR_CH_QUPU_FLOY.csv",header=F)
# or
#d<-read.csv("UPR_CH_TRVE_FLOY.csv",header=F)


# Make ch into a matrix
ch <- as.matrix(d)
dimnames(ch) <- NULL

# Get first captures for primaries
firsts<-function(x=x){min(which(x>0))}
fc <- apply(ch, 1, firsts)
fc <- ceiling(fc/3)


# Mark-recapture sampling regime
n.sec.occ <- 3                  # Secondary occasions
n.years <- 5                    # Primary occasions


n <- nrow(ch)                   # Individuals

# . Array formatting ----  
# Create 3-d array to hold observations
obs <- array(NA, c(n, n.years, n.sec.occ))

# Fill the observation array
# from the full ch
for (i in 1:(n)){
  for (t in fc[i]:n.years){
    for (j in 1:n.sec.occ){
      obs[i,t,j] <- ch[i, (t+n.years*(j-1))]
    }
  }
}
obs[is.na(obs)] <- 0

# . Primary period capture histories ----  
ch2 <- cbind(apply(ch[,1:3], 1, sum),
             apply(ch[,4:6], 1, sum),
             apply(ch[,7:9], 1, sum),
             apply(ch[,10:12], 1, sum),
             apply(ch[,13:15], 1, sum))
ch2[ch2>0] <- 1


# . Secondary period capture histories ----
test <- matrix(NA, n, n.years)
for (i in 1:nrow(test)){
  for (j in 1:ncol(test)){
    test[i,j] <- sum(obs[i,j,1:n.sec.occ])
  }
}

# Create seen/missed matrices used to build
# the yes/no/total matrices for binomial 
# detection model.
seen <- array(0, c(n, n.years, n.sec.occ))
missed <- array(0, c(n, n.years, n.sec.occ))

# Fill in the arrays  
for (i in 1:nrow(test)){
  for (t in 1:ncol(test)){
    for (j in 1:n.sec.occ){
      if(test[i,t] >= 1 & obs[i,t,j] == 1){seen[i,t,j] <- 1}
      if(test[i,t] >= 1 & obs[i,t,j] == 0){missed[i,t,j] <- 1}
    }
  }
}

# Create 2-d array to hold yes/no data

yes <- matrix(NA, n.years, n.sec.occ)
no <- matrix(NA, n.years, n.sec.occ)


### THIS SEEMS TO BE FILLING BACKWARD
### LIKELY BECAUSE I BUILD RAGGED CH
### ARRAY BACKWARD AT START
for (i in 1:n.years){
  for (j in 1:n.sec.occ){
    yes[i,j] <- sum(seen[,i,j])
    no[i,j] <- sum(missed[,i,j])
  }
}

### NLIST AND RE-ORDERING FOR NOW
yes <- matrix(c(yes), ncol=3, byrow = TRUE)
no <- matrix(c(no), ncol=3, byrow = TRUE)
total <- yes + no


# Model specification ----
modelString = "
model {
# Priors
# Survival and gamma
    for(t in 1:(n.years-1)){
      phi[t] ~ dbeta(1,1)    
      gamma[t] ~ dbeta(1,1) 
  }
# Secondary occasions p
    for (t in 1:n.years){
    for (j in 1:(n.sec[t])){
      p[t,j] ~ dunif(0,1)
      yes[t,j] ~ dbin(p[t,j], total[t,j])
    }
  }   

#mean.p ~ dunif(0,1) 
# Primary occasions p
    for (t in 1:n.years){
      pstar[t] <- 1 - prod(1 - p[t,])
  }
# Likelihood
    for (i in 1:n.ind){

      z[i,first[i]] <- ch[i,first[i]]
# phi adjusted for probability of losing tag
    for (t in (first[i]+1):n.years){
      ##mu1[i,t] <- z[i,t-1] * phi[t-1]##
      mu1[i,t] <- z[i,t-1] * (phi[t-1] * 0.947) #adjust this value for prob of (not) losing tag
      mu2[i,t] <- z[i,t] * gamma[t-1] * pstar[t]
      z[i,t] ~ dbern(mu1[i,t])
      ch[i,t] ~ dbern(mu2[i,t])
    } 

  } # end likelihood

## pop abundances
# adjusted for probability of losing both PIT and floy
    for(t in 1:n.years){
        Nin[t] <- (sum(ch[,t])/pstar[t]) * 0.947
    }


} # end model
"

# Model calibration ----
#.Bundle data ----
# Get first capture for primaries
first <- apply(ch2, 1, firsts)  

# Bundle the data for JAGS  
dat <- list(first=first,
            ch = ch2,
            n.sec = rep(n.sec.occ, n.years),
            n.years = ncol(ch2),
            n.ind = nrow(ch2),
            yes = yes,
            total = total
)

# . Initial Values ----
z.init <- matrix(NA, nrow(ch2), ncol(ch2))
for (i in 1:nrow(ch2)){
  if(first[i] < ncol(z.init)){
    z.init[i, (first[i] + 1):ncol(z.init)] <- 1
  }
}

inits <- function(){list(z = z.init)}  

# . Parameters to monitor ----
pars <- c('pstar', 'gamma', 'p', 'phi','Nin')

# . MCMC settings ----
nc <- 3
nt <- 10
ni <- 15000
nb <- 5000

# . Call JAGS and run model ----
rdt <- jags(dat, inits=inits, pars,
            model.file=textConnection(modelString), 
            n.chains = nc, n.iter = ni,
            n.burnin = nb, n.thin = nt,
            refresh = 0.001
)

# . Print model summary ----
print(rdt,digits=3)

